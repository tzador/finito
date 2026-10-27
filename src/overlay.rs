//! Click-through, transparent overlay windows that cover displays and play the leaf show.
//!
//! Normally a process drives exactly one display (see `main.rs`); this module still copes with
//! several so the fallback path can cover every screen from one process.
use crate::atlas::Atlas;
use crate::render::{Gpu, Target};
use crate::scene::{Scene, Sprite};
use objc2_app_kit::{NSColor, NSScreenSaverWindowLevel, NSView, NSWindowCollectionBehavior};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use std::sync::Arc;
use std::time::Instant;
use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop};
use winit::platform::macos::{
    ActivationPolicy, EventLoopBuilderExtMacOS, MonitorHandleExtMacOS, WindowAttributesExtMacOS,
};
use winit::window::{Window, WindowId, WindowLevel};

/// Covers `displays` (Core Graphics display IDs, or `None` for every connected display) with
/// a leaf show composed from `seed` and returns once the last leaf has left every screen.
pub fn run(seed: u32, displays: Option<Vec<u32>>) -> Result<(), String> {
    let event_loop = EventLoop::builder()
        .with_activation_policy(ActivationPolicy::Accessory)
        .with_default_menu(false)
        .with_activate_ignoring_other_apps(false)
        .build()
        .map_err(|e| format!("could not start the event loop: {e}"))?;
    event_loop.set_control_flow(ControlFlow::Wait);
    let mut app = App {
        seed,
        displays,
        atlas: Atlas::load(),
        gpu: None,
        overlays: Vec::new(),
        error: None,
    };
    event_loop
        .run_app(&mut app)
        .map_err(|e| format!("event loop failed: {e}"))?;
    match app.error.take() {
        Some(error) => Err(error),
        None => Ok(()),
    }
}

struct App {
    seed: u32,
    displays: Option<Vec<u32>>,
    atlas: Atlas,
    gpu: Option<Gpu>,
    overlays: Vec<Overlay>,
    error: Option<String>,
}

struct Overlay {
    window: Arc<Window>,
    target: Target,
    scene: Scene,
    last_frame: Option<Instant>,
    sprites: Vec<Sprite>,
}

impl App {
    fn open_windows(&mut self, event_loop: &ActiveEventLoop) -> Result<(), String> {
        let monitors: Vec<_> = event_loop
            .available_monitors()
            .filter(|m| {
                self.displays
                    .as_ref()
                    .map(|ids| ids.contains(&m.native_id()))
                    .unwrap_or(true)
            })
            .collect();
        if monitors.is_empty() {
            // Nothing to show (sound-only process, or the display was unplugged between spawn
            // and launch): finish right away.
            return Ok(());
        }

        let instance = Gpu::instance();
        for monitor in monitors {
            let scale = monitor.scale_factor();
            let position = monitor.position().to_logical::<f64>(scale);
            let size = monitor.size().to_logical::<f64>(scale);
            let attributes = Window::default_attributes()
                .with_title("finito")
                .with_decorations(false)
                .with_transparent(true)
                .with_resizable(false)
                .with_position(position)
                .with_inner_size(size)
                .with_active(false)
                .with_window_level(WindowLevel::AlwaysOnTop)
                .with_has_shadow(false)
                .with_accepts_first_mouse(false);
            let window = Arc::new(
                event_loop
                    .create_window(attributes)
                    .map_err(|e| format!("could not open a window: {e}"))?,
            );
            let _ = window.set_cursor_hittest(false);
            configure_ns_window(&window);

            let surface = Gpu::create_surface(&instance, window.clone())?;
            if self.gpu.is_none() {
                self.gpu = Some(Gpu::new(instance.clone(), &surface, &self.atlas)?);
            }
            let gpu = self.gpu.as_ref().unwrap();

            let pixels = window.inner_size();
            let points = pixels.to_logical::<f32>(window.scale_factor());
            let target = gpu.target(surface, pixels.width, pixels.height, [points.width, points.height]);
            let mut scene = Scene::new(points.width, points.height, self.seed, self.atlas.aspects());
            scene.burst();
            window.request_redraw();
            self.overlays.push(Overlay {
                window,
                target,
                scene,
                last_frame: None,
                sprites: Vec::new(),
            });
        }
        Ok(())
    }

    fn redraw(&mut self, id: WindowId) {
        let Some(gpu) = self.gpu.as_ref() else { return };
        let Some(overlay) = self.overlays.iter_mut().find(|o| o.window.id() == id) else {
            return;
        };
        let now = Instant::now();
        let dt = overlay
            .last_frame
            .map(|last| now.duration_since(last).as_secs_f32().min(1.0 / 30.0))
            .unwrap_or(1.0 / 60.0);
        overlay.last_frame = Some(now);
        overlay.scene.update(dt);
        overlay.scene.sprites(&mut overlay.sprites);
        gpu.render(&mut overlay.target, &overlay.window, &overlay.sprites);
        if !overlay.scene.is_idle() {
            overlay.window.request_redraw();
        }
    }
}

impl ApplicationHandler for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if !self.overlays.is_empty() || self.error.is_some() {
            return;
        }
        match self.open_windows(event_loop) {
            Ok(()) if self.overlays.is_empty() => event_loop.exit(),
            Ok(()) => {}
            Err(error) => {
                self.error = Some(error);
                event_loop.exit();
            }
        }
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, id: WindowId, event: WindowEvent) {
        match event {
            WindowEvent::RedrawRequested => {
                self.redraw(id);
                if self.overlays.iter().all(|o| o.scene.is_idle()) {
                    for overlay in &self.overlays {
                        overlay.window.set_visible(false);
                    }
                    event_loop.exit();
                }
            }
            WindowEvent::CloseRequested | WindowEvent::Destroyed => event_loop.exit(),
            _ => {}
        }
    }
}

/// The bits winit does not expose: float above everything including the menu bar and
/// full-screen apps, follow every Space, and let clicks fall through.
fn configure_ns_window(window: &Window) {
    let Ok(handle) = window.window_handle() else { return };
    let RawWindowHandle::AppKit(handle) = handle.as_raw() else {
        return;
    };
    // SAFETY: winit hands out the NSView of a window it owns, on the main thread.
    let view = unsafe { &*(handle.ns_view.as_ptr() as *const NSView) };
    let Some(ns_window) = view.window() else { return };
    ns_window.setLevel(NSScreenSaverWindowLevel);
    ns_window.setCollectionBehavior(
        NSWindowCollectionBehavior::CanJoinAllSpaces
            | NSWindowCollectionBehavior::Stationary
            | NSWindowCollectionBehavior::FullScreenAuxiliary
            | NSWindowCollectionBehavior::IgnoresCycle,
    );
    ns_window.setIgnoresMouseEvents(true);
    ns_window.setHasShadow(false);
    ns_window.setOpaque(false);
    ns_window.setBackgroundColor(Some(&NSColor::clearColor()));
    ns_window.orderFrontRegardless();
}
