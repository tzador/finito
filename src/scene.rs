//! Autumn leaves drifting across the screen.
//!
//! A leaf does not fall straight. It glides sideways on a tilt, stalls at the end of the glide,
//! drops a little faster while it swings back, and banks into the new direction. Most leaves
//! only rock about their long axis; some tumble right over. A slowly changing wind field, with
//! a gust at the start of some shows, pushes the whole cloud around. Far leaves are smaller,
//! slower and dimmer than near ones, which gives the cloud some depth.
//!
//! The show itself (launch pattern, wind, density, duration) is composed from a seed, so every
//! launch looks a little different. Coordinates are in points with the origin at the bottom
//! left of the screen; the renderer maps them onto the display.
use crate::rng::SeededRandom;
use std::f32::consts::PI;

/// What the renderer needs to draw one leaf this frame.
#[derive(Clone, Copy, Debug)]
pub struct Sprite {
    pub position: [f32; 2],
    /// Unscaled width and height of the sprite in points.
    pub size: [f32; 2],
    pub rotation: f32,
    /// Horizontal squash for the rocking and tumbling, 0.1 ... 1.
    pub x_scale: f32,
    pub alpha: f32,
    /// How far the colour is blended toward black, 0 ... 1.
    pub blend: f32,
    pub texture: usize,
    pub depth: f32,
}

struct Leaf {
    sprite: Sprite,
    position: [f32; 2],
    velocity: [f32; 2],
    depth: f32,           // 0.55 (far: small, slow, dim) ... 1 (near)
    size: f32,            // long axis in points
    descent: f32,         // steady fall speed, points per second
    response: f32,        // how quickly velocity relaxes toward the glide, per second
    glide_speed: f32,     // horizontal speed at the middle of a glide
    glide_frequency: f32, // radians per second
    glide_phase: f32,
    rotation: f32,
    spin: f32, // steady rotation, radians per second
    bank: f32, // how far the leaf tilts into its glide, radians
    flip: f32,
    flip_speed: f32,
    flip_range: Option<f32>, // rocking amplitude in radians, or None for tumblers
    age: f32,
    life: f32,
}

#[derive(Clone, Copy)]
enum Source {
    Fall,
    Gust { from_left: bool },
    Swirl { origin: [f32; 2], angle: f32, power: f32 },
}

/// Emits leaves for a duration at a rate.
struct Spawner {
    delay: f32,     // seconds before it starts
    remaining: f32, // seconds left once started
    rate: f32,      // leaves per second
    accumulator: f32,
    source: Source,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Pattern {
    Fall,
    Gust,
    Swirl,
    Everything,
}

const PATTERNS: [Pattern; 4] = [Pattern::Fall, Pattern::Gust, Pattern::Swirl, Pattern::Everything];

/// What this launch looks like, decided once from the seed.
struct Design {
    pattern: Pattern,
    gust_from_left: bool,
    wind_strength: f32,
    density: f32,
    duration: f32, // seconds of steady fall from the top
}

pub struct Scene {
    width: f32,
    height: f32,
    design: Design,
    leaves: Vec<Leaf>,
    spawners: Vec<Spawner>,
    aspects: Vec<f32>,
    elapsed: f32,
    rng: SeededRandom,
}

const MAX_LEAVES: usize = 700;

impl Scene {
    /// `aspects` is width over height for every leaf texture the renderer can draw.
    pub fn new(width: f32, height: f32, seed: u32, aspects: Vec<f32>) -> Scene {
        let mut rng = SeededRandom::new(seed.wrapping_add(0x5EED));
        let design = Design {
            pattern: PATTERNS[rng.index(PATTERNS.len())],
            gust_from_left: rng.next_unit() < 0.5,
            wind_strength: 0.4 + rng.next_unit() * 0.9,
            density: 0.75 + rng.next_unit() * 0.6,
            duration: 0.7 + rng.next_unit() * 0.6,
        };
        assert!(!aspects.is_empty(), "the scene needs at least one leaf texture");
        Scene {
            width,
            height,
            design,
            leaves: Vec::new(),
            spawners: Vec::new(),
            aspects,
            elapsed: 0.0,
            rng: SeededRandom::new(seed.rotate_left(16) ^ 0x1EAF_1EAF),
        }
    }

    pub fn is_idle(&self) -> bool {
        self.leaves.is_empty() && self.spawners.is_empty()
    }

    // MARK: - Firing

    pub fn burst(&mut self) {
        let w = self.width;
        let density = self.design.density;
        let spawners = &mut self.spawners;
        let design = &self.design;

        fn fall(spawners: &mut Vec<Spawner>, density: f32, duration: f32, rate: f32, delay: f32) {
            spawners.push(Spawner {
                delay,
                remaining: duration,
                rate: rate * density,
                accumulator: 0.0,
                source: Source::Fall,
            });
        }
        fn gust(spawners: &mut Vec<Spawner>, density: f32, from_left: bool, duration: f32, rate: f32) {
            spawners.push(Spawner {
                delay: 0.0,
                remaining: duration,
                rate: rate * density,
                accumulator: 0.0,
                source: Source::Gust { from_left },
            });
        }
        fn swirl(spawners: &mut Vec<Spawner>, density: f32, origin: [f32; 2], angle: f32, delay: f32) {
            spawners.push(Spawner {
                delay,
                remaining: 0.15,
                rate: 600.0 * density,
                accumulator: 0.0,
                source: Source::Swirl {
                    origin,
                    angle,
                    power: 1.0,
                },
            });
            spawners.push(Spawner {
                delay,
                remaining: 0.4,
                rate: 100.0 * density,
                accumulator: 0.0,
                source: Source::Swirl {
                    origin,
                    angle,
                    power: 0.75,
                },
            });
        }

        match design.pattern {
            Pattern::Fall => {
                // A steady shower from above, nothing else.
                fall(spawners, density, design.duration + 0.2, 140.0, 0.0);
            }
            Pattern::Gust => {
                // A gust sweeps a cloud of leaves in from one side, and a few more keep falling after.
                gust(spawners, density, design.gust_from_left, 0.55, 250.0);
                fall(spawners, density, design.duration * 0.7, 75.0, 0.15);
            }
            Pattern::Swirl => {
                // Leaves kicked up from both bottom corners, whirling up before they settle.
                swirl(spawners, density, [w * 0.04, -20.0], PI / 2.0 - 0.55, 0.0);
                swirl(spawners, density, [w * 0.96, -20.0], PI / 2.0 + 0.55, 0.07);
                fall(spawners, density, design.duration * 0.6, 80.0, 0.1);
            }
            Pattern::Everything => {
                gust(spawners, density, design.gust_from_left, 0.4, 210.0);
                let corner = if design.gust_from_left {
                    [w * 0.96, -20.0]
                } else {
                    [w * 0.04, -20.0]
                };
                let angle = if design.gust_from_left {
                    PI / 2.0 + 0.55
                } else {
                    PI / 2.0 - 0.55
                };
                swirl(spawners, density, corner, angle, 0.12);
                fall(spawners, density, design.duration, 105.0, 0.1);
            }
        }
    }

    fn make_from(&mut self, source: Source) -> Leaf {
        match source {
            Source::Fall => self.falling_leaf(),
            Source::Gust { from_left } => self.gust_leaf(from_left),
            Source::Swirl { origin, angle, power } => self.swirl_leaf(origin, angle, power),
        }
    }

    fn falling_leaf(&mut self) -> Leaf {
        let (w, h) = (self.width, self.height);
        let depth = self.random_depth();
        let x = self.rng.range(-w * 0.05, w * 1.05);
        let dy = -h * self.rng.range(0.3, 0.7) * depth;
        let dx = self.wind(h, depth);
        self.make_leaf(depth, [x, h + h * 0.08], [dx, dy])
    }

    fn gust_leaf(&mut self, from_left: bool) -> Leaf {
        let (w, h) = (self.width, self.height);
        let depth = self.random_depth();
        let speed = h * self.rng.range(1.4, 2.4) * depth;
        let rise = h * self.rng.range(-0.1, 0.45) * depth;
        let y = self.rng.range(h * 0.1, h * 1.05);
        let x = if from_left { -h * 0.1 } else { w + h * 0.1 };
        self.make_leaf(depth, [x, y], [if from_left { speed } else { -speed }, rise])
    }

    fn swirl_leaf(&mut self, origin: [f32; 2], angle: f32, power: f32) -> Leaf {
        let h = self.height;
        let depth = self.random_depth();
        let spread = self.rng.range(-0.5, 0.5);
        let theta = angle + spread * spread.abs() * 2.2;
        let speed = h * self.rng.range(1.6, 2.9) * power * depth;
        let x = origin[0] + self.rng.range(-30.0, 30.0);
        self.make_leaf(depth, [x, origin[1]], [theta.cos() * speed, theta.sin() * speed])
    }

    fn random_depth(&mut self) -> f32 {
        // Skewed toward near leaves so the big, bright ones dominate.
        0.55 + 0.45 * self.rng.next_unit().sqrt()
    }

    fn make_leaf(&mut self, depth: f32, position: [f32; 2], velocity: [f32; 2]) -> Leaf {
        let h = self.height;
        let rng = &mut self.rng;
        let texture = rng.index(self.aspects.len());
        let aspect = self.aspects[texture];
        let long_axis = h * rng.range(0.042, 0.07) * depth;
        let size = if aspect >= 1.0 {
            [long_axis, long_axis / aspect]
        } else {
            [long_axis * aspect, long_axis]
        };
        let tumbles = rng.next_unit() < 0.22;
        let rotation = rng.range(0.0, 2.0 * PI);
        let alpha = 0.7 + 0.3 * depth;
        Leaf {
            sprite: Sprite {
                position,
                size,
                rotation,
                x_scale: 1.0,
                alpha,
                blend: 0.2 * (1.0 - depth),
                texture,
                depth,
            },
            position,
            velocity,
            depth,
            size: long_axis,
            descent: h * rng.range(0.6, 0.95) * depth,
            response: rng.range(2.5, 4.5),
            glide_speed: h * rng.range(0.25, 0.55) * depth,
            glide_frequency: rng.range(2.8, 5.0),
            glide_phase: rng.range(0.0, 2.0 * PI),
            rotation,
            spin: rng.range(-0.9, 0.9),
            bank: rng.range(0.25, 0.6),
            flip: rng.range(0.0, 2.0 * PI),
            flip_speed: if tumbles {
                rng.range(3.0, 7.0) * if rng.chance(0.5) { 1.0 } else { -1.0 }
            } else {
                rng.range(0.8, 2.2)
            },
            flip_range: if tumbles { None } else { Some(rng.range(0.35, 1.1)) },
            age: 0.0,
            life: 6.0,
        }
    }

    // MARK: - Simulation

    /// Advances the show by `dt` seconds (the caller clamps it to something sane).
    pub fn update(&mut self, dt: f32) {
        self.elapsed += dt;
        self.spawn(dt);
        self.step(dt);
    }

    fn spawn(&mut self, dt: f32) {
        for i in (0..self.spawners.len()).rev() {
            if self.spawners[i].delay > 0.0 {
                self.spawners[i].delay -= dt;
                continue;
            }
            self.spawners[i].remaining -= dt;
            self.spawners[i].accumulator += self.spawners[i].rate * dt;
            let source = self.spawners[i].source;
            while self.spawners[i].accumulator >= 1.0 && self.leaves.len() < MAX_LEAVES {
                self.spawners[i].accumulator -= 1.0;
                let leaf = self.make_from(source);
                self.leaves.push(leaf);
            }
            if self.spawners[i].remaining <= 0.0 {
                self.spawners.remove(i);
            }
        }
    }

    /// Horizontal wind at a height, in points per second: a slowly wandering breeze plus, for
    /// gust shows, a strong push from the gust side that dies away over the first seconds.
    fn wind(&self, y: f32, depth: f32) -> f32 {
        let (h, t) = (self.height, self.elapsed);
        let design = &self.design;
        let breeze =
            ((t * 0.5).sin() * 0.5 + (t * 1.3 + 1.3).sin() * 0.3 + (t * 2.9 + 0.4).sin() * 0.15) * design.wind_strength;
        let mut wind = breeze * h * 0.14;
        if design.pattern == Pattern::Gust || design.pattern == Pattern::Everything {
            let push = h * 0.7 * design.wind_strength * (-t / 0.7).exp();
            wind += if design.gust_from_left { push } else { -push };
        }
        wind * (0.6 + 0.6 * (y / h).clamp(0.0, 1.0)) * depth
    }

    fn step(&mut self, dt: f32) {
        let (w, h, t) = (self.width, self.height, self.elapsed);

        for i in (0..self.leaves.len()).rev() {
            let wind = self.wind(self.leaves[i].position[1], self.leaves[i].depth);
            let leaf = &mut self.leaves[i];
            leaf.age += dt;

            // Glide: slide sideways, stall at the turn, drop faster while swinging back.
            let glide = (t * leaf.glide_frequency + leaf.glide_phase).cos();
            let stall = 1.0 - glide.abs();
            let target_x = leaf.glide_speed * glide + wind;
            let target_y = -leaf.descent * (0.7 + 0.6 * stall);
            let k = (leaf.response * dt).min(1.0);
            leaf.velocity[0] += (target_x - leaf.velocity[0]) * k;
            leaf.velocity[1] += (target_y - leaf.velocity[1]) * k;
            leaf.position[0] += leaf.velocity[0] * dt;
            leaf.position[1] += leaf.velocity[1] * dt;

            // Tumble while moving fast (gusts, swirls), settle into a lazy rock while drifting.
            let speed_factor = (leaf.velocity[0].hypot(leaf.velocity[1]) / (h * 0.9)).min(1.0);
            leaf.rotation += leaf.spin * (0.5 + 3.5 * speed_factor) * dt;
            leaf.flip += leaf.flip_speed * (0.6 + 2.4 * speed_factor) * dt;

            let fade = ((leaf.life - leaf.age) / 1.2).min(1.0);
            let margin = leaf.size * 2.0;
            let dead = leaf.age >= leaf.life
                || leaf.position[1] < -margin
                || leaf.position[0] < -w * 0.15 - margin
                || leaf.position[0] > w * 1.15 + margin;
            if dead {
                self.leaves.swap_remove(i);
                continue;
            }

            let flip_angle = match leaf.flip_range {
                Some(range) => range * leaf.flip.sin(),
                None => leaf.flip,
            };
            let facing = flip_angle.cos().abs();
            let sprite = &mut leaf.sprite;
            sprite.position = leaf.position;
            sprite.rotation = leaf.rotation + leaf.bank * glide;
            sprite.x_scale = facing.max(0.1);
            // Edge-on leaves catch less light; far leaves sit a little in the haze.
            sprite.blend = 0.4 * (1.0 - facing) + 0.2 * (1.0 - leaf.depth);
            sprite.alpha = (0.7 + 0.3 * leaf.depth) * fade;
        }
    }

    /// The sprites to draw this frame, far leaves first so near ones land on top.
    pub fn sprites(&self, out: &mut Vec<Sprite>) {
        out.clear();
        out.extend(self.leaves.iter().map(|leaf| leaf.sprite));
        out.sort_by(|a, b| a.depth.partial_cmp(&b.depth).unwrap_or(std::cmp::Ordering::Equal));
    }
}
