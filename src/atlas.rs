//! The embedded leaf atlas: one premultiplied RGBA texture of every leaf plus its mip chain.
use std::io::Cursor;

include!(concat!(env!("OUT_DIR"), "/leaf_atlas_rects.rs"));

static PNG: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/leaf_atlas.png"));

pub struct Atlas {
    pub width: u32,
    pub height: u32,
    /// Mip levels from full size down, each premultiplied RGBA8 of `width >> level` by
    /// `height >> level` pixels.
    pub mips: Vec<(u32, u32, Vec<u8>)>,
    /// [x, y, w, h] cells in level-0 pixels, origin top-left.
    pub rects: &'static [[u16; 4]],
}

impl Atlas {
    pub fn load() -> Atlas {
        let decoder = png::Decoder::new(Cursor::new(PNG));
        let mut reader = decoder.read_info().expect("embedded atlas is a valid PNG");
        let mut buf = vec![0u8; reader.output_buffer_size().expect("atlas buffer size")];
        let info = reader.next_frame(&mut buf).expect("decode embedded atlas");
        assert_eq!(info.color_type, png::ColorType::Rgba);
        assert_eq!(info.bit_depth, png::BitDepth::Eight);
        assert_eq!((info.width, info.height), (ATLAS_WIDTH, ATLAS_HEIGHT));
        buf.truncate(info.buffer_size());

        let mut mips = vec![(ATLAS_WIDTH, ATLAS_HEIGHT, buf)];
        loop {
            let (w, h, src) = mips.last().unwrap();
            if *w <= 1 || *h <= 1 {
                break;
            }
            let (nw, nh) = (w / 2, h / 2);
            let mut dst = vec![0u8; (nw * nh * 4) as usize];
            for y in 0..nh {
                for x in 0..nw {
                    for c in 0..4 {
                        let sample = |dx: u32, dy: u32| src[(((2 * y + dy) * w + 2 * x + dx) * 4 + c) as usize] as u32;
                        let sum = sample(0, 0) + sample(1, 0) + sample(0, 1) + sample(1, 1);
                        dst[((y * nw + x) * 4 + c) as usize] = ((sum + 2) / 4) as u8;
                    }
                }
            }
            mips.push((nw, nh, dst));
        }

        Atlas {
            width: ATLAS_WIDTH,
            height: ATLAS_HEIGHT,
            mips,
            rects: RECTS,
        }
    }

    /// Width over height of every leaf, in the order of `rects`.
    pub fn aspects(&self) -> Vec<f32> {
        self.rects.iter().map(|r| r[2] as f32 / r[3] as f32).collect()
    }

    /// Normalised [u, v, width, height] of a leaf in the atlas.
    pub fn uv_rect(&self, index: usize) -> [f32; 4] {
        let r = self.rects[index];
        [
            r[0] as f32 / self.width as f32,
            r[1] as f32 / self.height as f32,
            r[2] as f32 / self.width as f32,
            r[3] as f32 / self.height as f32,
        ]
    }
}
