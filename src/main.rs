use pollster::FutureExt;

fn main() {
    env_logger::init();
    raytracer::run().block_on().unwrap();
}
