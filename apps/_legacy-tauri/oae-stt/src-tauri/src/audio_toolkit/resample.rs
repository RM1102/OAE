use rubato::{FastFixedIn, PolynomialDegree, Resampler};

/// Resample mono f32 PCM from `fs_in` Hz to 16_000 Hz.
pub fn resample_mono_to_16k(mono: &[f32], fs_in: u32) -> anyhow::Result<Vec<f32>> {
    if fs_in == 16_000 {
        return Ok(mono.to_vec());
    }
    let ratio = 16_000f64 / fs_in as f64;
    let chunk = 1024;
    let mut resampler = FastFixedIn::<f32>::new(ratio, 1.0, PolynomialDegree::Cubic, chunk, 1)
        .map_err(|e| anyhow::anyhow!("resampler: {e}"))?;

    let mut out: Vec<f32> = Vec::with_capacity((mono.len() as f64 * ratio) as usize + chunk);
    let mut pos = 0usize;
    while pos < mono.len() {
        let end = (pos + chunk).min(mono.len());
        let mut frame: Vec<f32> = mono[pos..end].to_vec();
        if frame.len() < chunk {
            frame.resize(chunk, 0.0);
        }
        let waves_out = resampler
            .process(&[&frame], None)
            .map_err(|e| anyhow::anyhow!("process: {e}"))?;
        if !waves_out[0].is_empty() {
            out.extend_from_slice(&waves_out[0]);
        }
        pos = end;
    }
    // Drain delay lines
    loop {
        let waves_out = resampler
            .process_partial::<Vec<f32>>(None, None)
            .map_err(|e| anyhow::anyhow!("partial: {e}"))?;
        if waves_out[0].is_empty() {
            break;
        }
        out.extend_from_slice(&waves_out[0]);
    }
    Ok(out)
}
