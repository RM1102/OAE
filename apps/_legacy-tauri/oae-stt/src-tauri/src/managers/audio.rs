use crate::audio_toolkit::resample::resample_mono_to_16k;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use parking_lot::Mutex;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::Duration;
use tauri::Emitter;
use tauri::AppHandle;

pub struct AudioService {
    raw_input: Arc<Mutex<Vec<f32>>>,
    sample_rate_hz: Arc<Mutex<u32>>,
    recording: Arc<AtomicBool>,
    level_bits: Arc<AtomicU32>,
    stop_tx: Mutex<Option<Sender<()>>>,
    worker_thread: Mutex<Option<JoinHandle<()>>>,
    level_thread: Mutex<Option<JoinHandle<()>>>,
}

impl AudioService {
    pub fn new() -> Self {
        Self {
            raw_input: Arc::new(Mutex::new(Vec::new())),
            sample_rate_hz: Arc::new(Mutex::new(16_000)),
            recording: Arc::new(AtomicBool::new(false)),
            level_bits: Arc::new(AtomicU32::new(0.0f32.to_bits())),
            stop_tx: Mutex::new(None),
            worker_thread: Mutex::new(None),
            level_thread: Mutex::new(None),
        }
    }

    pub fn list_input_devices(&self) -> anyhow::Result<Vec<String>> {
        let host = cpal::default_host();
        let mut names = Vec::new();
        if let Some(d) = host.default_input_device() {
            if let Ok(n) = d.name() {
                names.push(n);
            }
        }
        for d in host.input_devices()? {
            if let Ok(n) = d.name() {
                if !names.contains(&n) {
                    names.push(n);
                }
            }
        }
        Ok(names)
    }

    fn pick_device(name: Option<&str>) -> anyhow::Result<cpal::Device> {
        let host = cpal::default_host();
        let device = if let Some(n) = name {
            host.input_devices()?
                .find(|d| d.name().map(|dn| dn == n).unwrap_or(false))
                .ok_or_else(|| anyhow::anyhow!("microphone not found: {n}"))?
        } else {
            host.default_input_device()
                .ok_or_else(|| anyhow::anyhow!("no default input device"))?
        };
        Ok(device)
    }

    fn downmix_to_mono(interleaved: &[f32], channels: usize) -> Vec<f32> {
        if channels <= 1 {
            return interleaved.to_vec();
        }
        interleaved
            .chunks(channels)
            .map(|frame| frame.iter().copied().sum::<f32>() / channels as f32)
            .collect()
    }

    fn push_chunk(raw_input: &Arc<Mutex<Vec<f32>>>, level_bits: &Arc<AtomicU32>, chunk: &[f32]) {
        if chunk.is_empty() {
            return;
        }
        let mut raw = raw_input.lock();
        raw.extend_from_slice(chunk);
        drop(raw);

        let rms = (chunk.iter().map(|x| x * x).sum::<f32>() / chunk.len() as f32).sqrt();
        level_bits.store(rms.to_bits(), Ordering::Relaxed);
    }

    pub fn start(&self, device_name: Option<String>, app: AppHandle) -> anyhow::Result<()> {
        if self.recording.swap(true, Ordering::SeqCst) {
            return Err(anyhow::anyhow!("already recording"));
        }

        self.raw_input.lock().clear();
        self.level_bits.store(0.0f32.to_bits(), Ordering::Relaxed);

        let device = Self::pick_device(device_name.as_deref())?;
        let cfg = device.default_input_config()?;
        *self.sample_rate_hz.lock() = cfg.sample_rate().0;
        let channels = cfg.channels() as usize;
        let stream_cfg: cpal::StreamConfig = cfg.clone().into();
        let raw_input = self.raw_input.clone();
        let level_bits = self.level_bits.clone();
        let recording = self.recording.clone();
        let recording_for_worker = recording.clone();
        let (stop_tx, stop_rx) = std::sync::mpsc::channel::<()>();
        *self.stop_tx.lock() = Some(stop_tx);

        let worker = std::thread::spawn(move || {
            let stream_result = match cfg.sample_format() {
                cpal::SampleFormat::F32 => device.build_input_stream(
                    &stream_cfg,
                    move |data: &[f32], _| {
                        let mono = Self::downmix_to_mono(data, channels);
                        Self::push_chunk(&raw_input, &level_bits, &mono);
                    },
                    move |e| eprintln!("audio input stream error: {e}"),
                    None,
                ),
                cpal::SampleFormat::I16 => device.build_input_stream(
                    &stream_cfg,
                    move |data: &[i16], _| {
                        let f32_data: Vec<f32> =
                            data.iter().map(|v| *v as f32 / i16::MAX as f32).collect();
                        let mono = Self::downmix_to_mono(&f32_data, channels);
                        Self::push_chunk(&raw_input, &level_bits, &mono);
                    },
                    move |e| eprintln!("audio input stream error: {e}"),
                    None,
                ),
                cpal::SampleFormat::U16 => device.build_input_stream(
                    &stream_cfg,
                    move |data: &[u16], _| {
                        let f32_data: Vec<f32> = data
                            .iter()
                            .map(|v| (*v as f32 / u16::MAX as f32) * 2.0 - 1.0)
                            .collect();
                        let mono = Self::downmix_to_mono(&f32_data, channels);
                        Self::push_chunk(&raw_input, &level_bits, &mono);
                    },
                    move |e| eprintln!("audio input stream error: {e}"),
                    None,
                ),
                _ => return,
            };

            if let Ok(stream) = stream_result {
                if stream.play().is_ok() {
                    while recording_for_worker.load(Ordering::SeqCst) {
                        if stop_rx.try_recv().is_ok() {
                            break;
                        }
                        std::thread::sleep(Duration::from_millis(50));
                    }
                }
            }
        });
        *self.worker_thread.lock() = Some(worker);

        let level_bits = self.level_bits.clone();
        let level_thread = std::thread::spawn(move || {
            while recording.load(Ordering::SeqCst) {
                let level = f32::from_bits(level_bits.load(Ordering::Relaxed));
                let _ = app.emit("mic-level", level);
                std::thread::sleep(Duration::from_millis(150));
            }
        });
        *self.level_thread.lock() = Some(level_thread);

        Ok(())
    }

    pub fn stop(&self) -> anyhow::Result<Vec<f32>> {
        self.recording.store(false, Ordering::SeqCst);
        if let Some(tx) = self.stop_tx.lock().take() {
            let _ = tx.send(());
        }
        if let Some(h) = self.worker_thread.lock().take() {
            let _ = h.join();
        }
        if let Some(h) = self.level_thread.lock().take() {
            let _ = h.join();
        }

        let sample_rate_hz = *self.sample_rate_hz.lock();
        let mut raw = self.raw_input.lock();
        let captured = raw.clone();
        raw.clear();
        drop(raw);

        if captured.is_empty() {
            return Ok(Vec::new());
        }
        if sample_rate_hz == 16_000 {
            return Ok(captured);
        }
        resample_mono_to_16k(&captured, sample_rate_hz).map_err(|e| anyhow::anyhow!(e.to_string()))
    }
}

impl Default for AudioService {
    fn default() -> Self {
        Self::new()
    }
}
