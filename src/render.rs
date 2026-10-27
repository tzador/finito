//! wgpu rendering of the leaf sprites onto transparent windows.
use crate::atlas::Atlas;
use crate::scene::Sprite;
use std::sync::Arc;
use winit::window::Window;

#[repr(C)]
#[derive(Clone, Copy)]
struct Instance {
    position: [f32; 2],
    size: [f32; 2],
    shape: [f32; 4],
    uv_rect: [f32; 4],
}

// SAFETY: plain `f32` fields with no padding.
unsafe impl bytemuck::Zeroable for Instance {}
unsafe impl bytemuck::Pod for Instance {}

#[repr(C)]
#[derive(Clone, Copy)]
struct Uniforms {
    screen: [f32; 2],
    _pad: [f32; 2],
}

// SAFETY: plain `f32` fields with no padding.
unsafe impl bytemuck::Zeroable for Uniforms {}
unsafe impl bytemuck::Pod for Uniforms {}

/// Everything shared between the windows of one process: device, pipeline and the atlas.
pub struct Gpu {
    _instance: wgpu::Instance,
    device: wgpu::Device,
    queue: wgpu::Queue,
    pipeline: wgpu::RenderPipeline,
    atlas_bind_group: wgpu::BindGroup,
    uniform_layout: wgpu::BindGroupLayout,
    format: wgpu::TextureFormat,
    alpha_mode: wgpu::CompositeAlphaMode,
    uv_rects: Vec<[f32; 4]>,
}

/// One window's surface and per-frame buffers.
pub struct Target {
    surface: wgpu::Surface<'static>,
    config: wgpu::SurfaceConfiguration,
    uniform_bind_group: wgpu::BindGroup,
    instances: wgpu::Buffer,
    capacity: usize,
    scratch: Vec<Instance>,
}

impl Gpu {
    pub fn instance() -> wgpu::Instance {
        wgpu::Instance::new(wgpu::InstanceDescriptor {
            backends: wgpu::Backends::METAL,
            ..wgpu::InstanceDescriptor::new_without_display_handle()
        })
    }

    /// Picks an adapter that can draw to `surface` and builds the sprite pipeline.
    pub fn new(instance: wgpu::Instance, surface: &wgpu::Surface<'static>, atlas: &Atlas) -> Result<Gpu, String> {
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::LowPower,
            compatible_surface: Some(surface),
            force_fallback_adapter: false,
            apply_limit_buckets: false,
        }))
        .map_err(|e| format!("no graphics adapter: {e}"))?;
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("finito"),
            ..Default::default()
        }))
        .map_err(|e| format!("no graphics device: {e}"))?;

        let caps = surface.get_capabilities(&adapter);
        let format = caps
            .formats
            .iter()
            .copied()
            .find(|f| !f.is_srgb())
            .unwrap_or(caps.formats[0]);
        let alpha_mode = [
            wgpu::CompositeAlphaMode::PreMultiplied,
            wgpu::CompositeAlphaMode::PostMultiplied,
        ]
        .into_iter()
        .find(|m| caps.alpha_modes.contains(m))
        .ok_or_else(|| "the surface does not support transparency".to_string())?;

        // Atlas texture with its mip chain.
        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("leaf atlas"),
            size: wgpu::Extent3d {
                width: atlas.width,
                height: atlas.height,
                depth_or_array_layers: 1,
            },
            mip_level_count: atlas.mips.len() as u32,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8Unorm,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        for (level, (w, h, pixels)) in atlas.mips.iter().enumerate() {
            queue.write_texture(
                wgpu::TexelCopyTextureInfo {
                    texture: &texture,
                    mip_level: level as u32,
                    origin: wgpu::Origin3d::ZERO,
                    aspect: wgpu::TextureAspect::All,
                },
                pixels,
                wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(4 * w),
                    rows_per_image: Some(*h),
                },
                wgpu::Extent3d {
                    width: *w,
                    height: *h,
                    depth_or_array_layers: 1,
                },
            );
        }
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("leaf sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::MipmapFilterMode::Linear,
            ..Default::default()
        });

        let atlas_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("atlas layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    count: None,
                },
            ],
        });
        let atlas_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("atlas"),
            layout: &atlas_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&sampler),
                },
            ],
        });
        let uniform_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("uniform layout"),
            entries: &[wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::VERTEX,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            }],
        });

        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("leaves"),
            source: wgpu::ShaderSource::Wgsl(include_str!("shader.wgsl").into()),
        });
        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("leaves"),
            bind_group_layouts: &[Some(&atlas_layout), Some(&uniform_layout)],
            immediate_size: 0,
        });
        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("leaves"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                compilation_options: Default::default(),
                buffers: &[Some(wgpu::VertexBufferLayout {
                    array_stride: std::mem::size_of::<Instance>() as u64,
                    step_mode: wgpu::VertexStepMode::Instance,
                    attributes: &wgpu::vertex_attr_array![0 => Float32x2, 1 => Float32x2, 2 => Float32x4, 3 => Float32x4],
                })],
            },
            primitive: wgpu::PrimitiveState::default(),
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                compilation_options: Default::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format,
                    blend: Some(wgpu::BlendState::PREMULTIPLIED_ALPHA_BLENDING),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            multiview_mask: None,
            cache: None,
        });

        Ok(Gpu {
            _instance: instance,
            device,
            queue,
            pipeline,
            atlas_bind_group,
            uniform_layout,
            format,
            alpha_mode,
            uv_rects: (0..atlas.rects.len()).map(|i| atlas.uv_rect(i)).collect(),
        })
    }

    pub fn create_surface(instance: &wgpu::Instance, window: Arc<Window>) -> Result<wgpu::Surface<'static>, String> {
        instance
            .create_surface(window)
            .map_err(|e| format!("could not create a surface: {e}"))
    }

    /// Configures `surface` for a window of `width` x `height` pixels showing `points` points.
    pub fn target(&self, surface: wgpu::Surface<'static>, width: u32, height: u32, points: [f32; 2]) -> Target {
        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format: self.format,
            width: width.max(1),
            height: height.max(1),
            present_mode: wgpu::PresentMode::Fifo,
            desired_maximum_frame_latency: 2,
            alpha_mode: self.alpha_mode,
            view_formats: vec![],
            color_space: Default::default(),
        };
        surface.configure(&self.device, &config);

        let uniforms = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("uniforms"),
            size: std::mem::size_of::<Uniforms>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        self.queue.write_buffer(
            &uniforms,
            0,
            bytemuck::bytes_of(&Uniforms {
                screen: points,
                _pad: [0.0; 2],
            }),
        );
        let uniform_bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("uniforms"),
            layout: &self.uniform_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: uniforms.as_entire_binding(),
            }],
        });

        let capacity = 1024;
        Target {
            surface,
            config,
            uniform_bind_group,
            instances: self.instance_buffer(capacity),
            capacity,
            scratch: Vec::with_capacity(capacity),
        }
    }

    fn instance_buffer(&self, capacity: usize) -> wgpu::Buffer {
        self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("instances"),
            size: (capacity * std::mem::size_of::<Instance>()) as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        })
    }

    /// Draws `sprites` onto the target's window and presents the frame.
    pub fn render(&self, target: &mut Target, window: &Window, sprites: &[Sprite]) {
        target.scratch.clear();
        target.scratch.extend(sprites.iter().map(|s| Instance {
            position: s.position,
            size: s.size,
            shape: [s.rotation, s.x_scale, s.alpha, s.blend],
            uv_rect: self.uv_rects[s.texture],
        }));
        if target.scratch.len() > target.capacity {
            target.capacity = target.scratch.len().next_power_of_two();
            target.instances = self.instance_buffer(target.capacity);
        }
        if !target.scratch.is_empty() {
            self.queue
                .write_buffer(&target.instances, 0, bytemuck::cast_slice(&target.scratch));
        }

        let frame = match target.surface.get_current_texture() {
            wgpu::CurrentSurfaceTexture::Success(frame) | wgpu::CurrentSurfaceTexture::Suboptimal(frame) => frame,
            wgpu::CurrentSurfaceTexture::Timeout => return,
            wgpu::CurrentSurfaceTexture::Occluded => return,
            wgpu::CurrentSurfaceTexture::Outdated | wgpu::CurrentSurfaceTexture::Lost => {
                target.surface.configure(&self.device, &target.config);
                return;
            }
            wgpu::CurrentSurfaceTexture::Validation => return,
        };
        let view = frame.texture.create_view(&wgpu::TextureViewDescriptor::default());
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("frame") });
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("leaves"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    depth_slice: None,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });
            if !target.scratch.is_empty() {
                pass.set_pipeline(&self.pipeline);
                pass.set_bind_group(0, &self.atlas_bind_group, &[]);
                pass.set_bind_group(1, &target.uniform_bind_group, &[]);
                pass.set_vertex_buffer(0, target.instances.slice(..));
                pass.draw(0..6, 0..target.scratch.len() as u32);
            }
        }
        self.queue.submit(Some(encoder.finish()));
        window.pre_present_notify();
        self.queue.present(frame);
    }
}
