use flume::bounded;
use wgpu::util::DeviceExt;

mod geometry;

pub async fn run() -> anyhow::Result<()> {
    let instance = wgpu::Instance::new(&Default::default());
    let adapter = instance.request_adapter(&Default::default()).await.unwrap();
    let (device, queue) = adapter
        .request_device(&wgpu::DeviceDescriptor {
            required_features: wgpu::Features::CLEAR_TEXTURE,
            ..Default::default()
        })
        .await
        .unwrap();

    let shader = device.create_shader_module(wgpu::include_wgsl!("simple_raytracer.wgsl"));
    let downscale_shader = device.create_shader_module(wgpu::include_wgsl!("downscale_ssaa.wgsl"));

    let texture_size = wgpu::Extent3d {
        width: 256,
        height: 256,
        depth_or_array_layers: 1,
    };

    let super_sampled_texture = device.create_texture(&wgpu::TextureDescriptor {
        size: wgpu::Extent3d {
            width: texture_size.width * 2,
            height: texture_size.height * 2,
            depth_or_array_layers: texture_size.depth_or_array_layers,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::STORAGE_BINDING,
        label: Some("super_sampled_texture"),
        view_formats: &[],
    });
    let super_sampled_texture_view =
        super_sampled_texture.create_view(&wgpu::TextureViewDescriptor::default());

    let target_texture = device.create_texture(&wgpu::TextureDescriptor {
        size: texture_size,
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUsages::TEXTURE_BINDING
            | wgpu::TextureUsages::STORAGE_BINDING
            | wgpu::TextureUsages::COPY_SRC,
        label: Some("target_texture"),
        view_formats: &[],
    });
    let target_texture_view = target_texture.create_view(&wgpu::TextureViewDescriptor::default());

    let texture_bind_group_layout =
        device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            entries: &[wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::StorageTexture {
                    access: wgpu::StorageTextureAccess::WriteOnly,
                    format: wgpu::TextureFormat::Rgba8Unorm,
                    view_dimension: wgpu::TextureViewDimension::D2,
                },
                count: None,
            }],
            label: Some("texture_bind_group_layout"),
        });

    let input_bind_group_layout =
        device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
            ],
            label: Some("input_bind_group_layout"),
        });

    let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("Compute Pipeline Layout"),
        bind_group_layouts: &[&texture_bind_group_layout, &input_bind_group_layout],
        push_constant_ranges: &[],
    });

    let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("Raytracer Compute Pipeline"),
        layout: Some(&pipeline_layout),
        module: &shader,
        entry_point: Some("main"),
        compilation_options: Default::default(),
        cache: Default::default(),
    });

    let target_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        layout: &texture_bind_group_layout,
        entries: &[wgpu::BindGroupEntry {
            binding: 0,
            resource: wgpu::BindingResource::TextureView(&super_sampled_texture_view),
        }],
        label: Some("target_bind_group"),
    });

    let downsample_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("Downsample Pipeline"),
        layout: None,
        module: &downscale_shader,
        entry_point: Some("main"),
        compilation_options: Default::default(),
        cache: Default::default(),
    });
    let downsample_bind_group_layout = downsample_pipeline.get_bind_group_layout(0);
    let downsample_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        layout: &downsample_bind_group_layout,
        entries: &[
            wgpu::BindGroupEntry {
                binding: 0,
                resource: wgpu::BindingResource::TextureView(&super_sampled_texture_view),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: wgpu::BindingResource::TextureView(&target_texture_view),
            },
        ],
        label: Some("downsample_bind_group"),
    });

    let sphere_input_data = vec![
        geometry::Sphere {
            center: (0.0, 0.0, 5.0).into(),
            surface: geometry::Surface {
                diffuse_color: (1.0, 1.0, 0.0, 1.0).into(),
                specular_color: (0.8, 0.8, 0.8, 1.0).into(),
                specular_intensity: 1000.0,
                _padding: [0.0; 3],
            },
            radius: 3.0,
            _padding: [0.0; 3],
        },
        geometry::Sphere {
            center: (-1.0, -2.0, 5.3).into(),
            surface: geometry::Surface {
                diffuse_color: (0.0, 0.0, 1.0, 1.0).into(),
                specular_color: (0.8, 0.8, 0.8, 1.0).into(),
                specular_intensity: 10.0,
                _padding: [0.0; 3],
            },
            radius: 1.5,
            _padding: [0.0; 3],
        },
    ];

    let triangle_input_data = vec![geometry::Triangle {
        vertices: [
            (3.0, -3.0, 4.0).into(),
            (-1.0, -1.0, 6.0).into(),
            (4.0, -0.5, 3.5).into(),
        ],
        surface: geometry::Surface {
            diffuse_color: (1.0, 0.0, 0.5, 1.0).into(),
            specular_color: (0.8, 0.8, 0.8, 1.0).into(),
            specular_intensity: 10.0,
            _padding: [0.0; 3],
        },
    }];

    let sphere_input_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("input spheres"),
        contents: bytemuck::cast_slice(&sphere_input_data),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::STORAGE,
    });

    let triangle_input_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("input triangles"),
        contents: bytemuck::cast_slice(&triangle_input_data),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::STORAGE,
    });

    let data_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("data_bind_group"),
        layout: &input_bind_group_layout,
        entries: &[
            wgpu::BindGroupEntry {
                binding: 0,
                resource: sphere_input_buffer.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: triangle_input_buffer.as_entire_binding(),
            },
        ],
    });

    let u32_size = std::mem::size_of::<u32>() as u32;

    let output_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        size: (texture_size.width * texture_size.height * u32_size) as wgpu::BufferAddress,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        label: None,
        mapped_at_creation: false,
    });

    let mut encoder = device.create_command_encoder(&Default::default());

    encoder.clear_texture(&target_texture, &Default::default());

    {
        let mut pass = encoder.begin_compute_pass(&Default::default());
        pass.set_pipeline(&pipeline);
        pass.set_bind_group(0, &target_bind_group, &[]);
        pass.set_bind_group(1, &data_bind_group, &[]);
        pass.dispatch_workgroups(texture_size.width / 8, texture_size.height / 8, 1);
        pass.set_pipeline(&downsample_pipeline);
        pass.set_bind_group(0, &downsample_bind_group, &[]);
        pass.dispatch_workgroups(texture_size.width / 8, texture_size.height / 8, 1);
    }

    encoder.copy_texture_to_buffer(
        wgpu::TexelCopyTextureInfo {
            aspect: wgpu::TextureAspect::All,
            texture: &target_texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
        },
        wgpu::TexelCopyBufferInfo {
            buffer: &output_buffer,
            layout: wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(u32_size * texture_size.width),
                rows_per_image: Some(texture_size.height),
            },
        },
        texture_size,
    );

    queue.submit([encoder.finish()]);

    {
        let (tx, rx) = bounded(1);

        output_buffer.map_async(wgpu::MapMode::Read, .., move |result| {
            tx.send(result).unwrap()
        });

        device.poll(wgpu::PollType::wait_indefinitely())?;

        rx.recv_async().await??;

        let output_data = output_buffer.get_mapped_range(..);

        use image::{ImageBuffer, Rgba};
        let buffer = ImageBuffer::<Rgba<u8>, _>::from_raw(
            texture_size.width,
            texture_size.height,
            output_data,
        )
        .unwrap();
        buffer.save("image.png").unwrap();
    }

    output_buffer.unmap();

    Ok(())
}
