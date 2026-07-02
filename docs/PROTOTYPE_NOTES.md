# Prototype Notes

## Current Mechanics

- Moped uses arcade velocity control for acceleration/braking and torque/angular velocity for leaning.
- Pizzas are rectangular `RigidBody2D` objects.
- The caddy is a mostly enclosed physical delivery slot on the rear of the moped.
- The tongue grabs loose pizzas and pulls them toward a mouse-controlled target using spring-like force.
- The MagnetZone and LoadZone only provide gentle alignment/counting logic inside the caddy.
- Loaded pizzas remain physical and can still wobble or fall loose.

## Current Tuning Values

### GameManager

- `pizza_count`: number of starting pizzas. Current scene override in `Main.tscn` is `2`.
- `finish_x`: finish line X position.
- `load_speed_threshold`: max speed for a pizza to count as loaded.
- `load_slot_distance`: distance to target slot required for loading.
- `load_confirm_time`: time required inside LoadZone before loading.
- `magnet_strength`, `magnet_damping`, `magnet_max_force`: gentle catch guidance.
- `holder_strength`, `holder_damping`, `holder_max_force`: soft holder settling.
- `holder_torque`, `holder_angular_damping`: pizza flattening in holder.

### Moped

- `acceleration`, `reverse_acceleration`, `brake_strength`: drive feel.
- `max_forward_speed`, `max_reverse_speed`: arcade speed caps.
- `lean_acceleration`, `lean_torque`, `max_angular_speed`: rotation/lean feel.
- `caddy_width`, `caddy_wall_height`, `caddy_wall_thickness`, `caddy_floor_thickness`: physical caddy size.
- `caddy_top_lip_size`, `caddy_cover_size`: partial cover/catcher behavior.

### Tongue

- `max_range`: max tongue reach.
- `latch_radius`: grab forgiveness.
- `spring_strength`, `damping_force`, `max_force`: rope/mouse target feel.
- `max_grabbed_angular_velocity`: spin limiter while grabbed.

## Known Issues

- The caddy is still generated in `moped.gd` because extracting compound collision safely needs more care.
- `PizzaCaddy.tscn` exists as an organization target, but the active physical caddy remains part of `Moped.tscn` behavior.
- Godot is not available on PATH in the current automation environment, so runtime checks must be done in the editor.

## Next Steps

- Playtest caddy retention on normal ramps, bumps, and jumps.
- Tune caddy cover size and wall height before adding content.
- Extract caddy collision into a reusable child scene only after verifying it can move with the moped without changing physics behavior.
- Add debug visibility toggles for MagnetZone and LoadZone.
- Add a short reset/recover flow if the moped flips over.
