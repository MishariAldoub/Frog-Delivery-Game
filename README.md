# Frog Pizza Moped Prototype

A small Godot 4 physics prototype about a frog delivering pizza boxes on a moped.

The goal is to test whether the core loop is fun:

- Drive a wobbly moped over rough terrain.
- Keep pizza boxes inside the rear delivery caddy.
- Recover fallen pizzas with the frog tongue.

This is not a polished game. It is a playable mechanics test.

## How To Run

1. Open this folder in Godot 4.
2. Run the project.
3. The main scene is `res://scenes/Main.tscn`.

## Controls

- `W`: Accelerate
- `S`: Brake / reverse
- `A`: Lean left
- `D`: Lean right
- Left mouse button: Hold to shoot/control tongue
- `R`: Restart

## Current Scene Organization

- `scenes/Main.tscn`: main entry point with `GameManager`
- `scenes/LevelTest.tscn`: prototype test level
- `scenes/Moped.tscn`: moped physics body
- `scenes/Frog.tscn`: frog drawing
- `scenes/PizzaBox.tscn`: pizza box rigid body
- `scenes/Tongue.tscn`: tongue controller
- `scenes/HUD.tscn`: UI
- `scenes/PizzaCaddy.tscn`: placeholder scene for future safe caddy extraction

Most gameplay code still lives in scripts. The refactor is intentionally gradual so the working prototype behavior stays intact.
