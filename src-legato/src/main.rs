use legato::{
    builder::{LegatoBuilder, Unconfigured}, config::Config, interface::AudioInterface, midi::{MidiPortKind, start_midi_thread}, ports::PortBuilder, spec::NodeDefinition
};
use legato_template::Plate480;

fn env_or<T: std::str::FromStr>(key: &str, default: T) -> T {
    std::env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}


fn main() {
    let graph_path = std::env::var("LEGATO_GRAPH").unwrap_or_else(|_| ".legato".into());
    let graph = std::fs::read_to_string(&graph_path).unwrap();

    let config = Config {
        sample_rate: env_or("LEGATO_SAMPLE_RATE", 48_000),
        block_size: env_or("LEGATO_BLOCK_SIZE", 256),
        channels: env_or("LEGATO_CHANNELS", 2),
        rt_capacity: env_or("LEGATO_RT_CAPACITY", 0),
    };

    let midi_rt_fe = start_midi_thread(
        256,
        "legato",
        MidiPortKind::Named("midi_capture_1"),
        MidiPortKind::Named("midi_playback_1"),
        "legato_din",
    ).unwrap();

    let ports = PortBuilder::default().audio_out(config.channels).build();
    
    let (app, _) = LegatoBuilder::<Unconfigured>::new(config, ports)
        .register_node("user", Plate480::spec())
        .set_midi_runtime(midi_rt_fe)
        .build_dsl(&graph);

    let host = cpal::host_from_id(cpal::HostId::Jack).unwrap();

    AudioInterface::builder(&host, config)
        .build(app)
        .expect("Failed to start audio")
        .run_forever();
}