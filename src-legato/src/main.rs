use legato::{
    builder::{LegatoBuilder, Unconfigured},
    config::Config,
    interface::AudioInterface,
    ports::PortBuilder,
};

fn env_or<T: std::str::FromStr>(key: &str, default: T) -> T {
    std::env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}

fn main() {
    let graph_path = std::env::var("LEGATO_GRAPH").unwrap_or_else(|_| ".legato".into());
    let graph = std::fs::read_to_string(&graph_path).unwrap();

    let config = Config {
        sample_rate: env_or("LEGATO_SAMPLE_RATE", 48_000),
        block_size: env_or("LEGATO_BLOCK_SIZE", 1024),
        channels: env_or("LEGATO_CHANNELS", 2),
        rt_capacity: env_or("LEGATO_RT_CAPACITY", 0),
    };

    let ports = PortBuilder::default().audio_out(config.channels).build();
    let (app, _) = LegatoBuilder::<Unconfigured>::new(config, ports).build_dsl(&graph);

    let host = cpal::host_from_id(cpal::HostId::Alsa).unwrap();

    AudioInterface::builder(&host, config)
        .build(app)
        .expect("Failed to start audio")
        .run_forever();
}