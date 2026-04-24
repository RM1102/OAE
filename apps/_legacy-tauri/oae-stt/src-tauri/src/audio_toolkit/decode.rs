use std::fs::File;
use std::path::Path;
use symphonia::core::audio::{AudioBufferRef, SampleBuffer};
use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error as SymError;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

/// Decode media to **mono f32** at the file's native sample rate.
pub fn decode_file_to_mono_f32(path: &Path) -> anyhow::Result<(Vec<f32>, u32)> {
    let file = File::open(path)?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }
    let probed = symphonia::default::get_probe().format(
        &hint,
        mss,
        &FormatOptions::default(),
        &MetadataOptions::default(),
    )?;
    let mut format = probed.format;

    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
        .ok_or_else(|| anyhow::anyhow!("no supported audio track"))?;
    let track_id = track.id;
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &DecoderOptions::default())
        .map_err(|e| anyhow::anyhow!("codec init: {e}"))?;

    let sample_rate = track
        .codec_params
        .sample_rate
        .ok_or_else(|| anyhow::anyhow!("unknown sample rate"))?;
    let ch_count = track.codec_params.channels.map(|c| c.count()).unwrap_or(1);

    let mut mono_out: Vec<f32> = Vec::new();

    loop {
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(SymError::ResetRequired) => continue,
            Err(SymError::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(e) => return Err(anyhow::anyhow!("packet: {e}")),
        };
        if packet.track_id() != track_id {
            continue;
        }
        let decoded = match decoder.decode(&packet) {
            Ok(d) => d,
            Err(SymError::DecodeError(_)) => continue,
            Err(e) => return Err(anyhow::anyhow!("decode: {e}")),
        };
        append_decoded(&decoded, ch_count, &mut mono_out)?;
    }

    Ok((mono_out, sample_rate))
}

fn append_decoded(
    decoded: &AudioBufferRef<'_>,
    ch_count: usize,
    mono_out: &mut Vec<f32>,
) -> anyhow::Result<()> {
    let spec = *decoded.spec();
    let duration = decoded.capacity() as u64;
    let mut buf = SampleBuffer::<f32>::new(duration, spec);
    buf.copy_interleaved_ref(decoded.clone());
    let interleaved = buf.samples();
    if ch_count <= 1 {
        mono_out.extend_from_slice(interleaved);
        return Ok(());
    }
    let frames = interleaved.len() / ch_count;
    for f in 0..frames {
        let base = f * ch_count;
        let mut sum = 0.0f32;
        for c in 0..ch_count {
            sum += interleaved[base + c];
        }
        mono_out.push(sum / ch_count as f32);
    }
    Ok(())
}
