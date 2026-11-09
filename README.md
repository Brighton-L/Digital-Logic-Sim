# Digital Logic Sim

Open `project.godot` in Godot 4.7 and run the project.

## Controls

- Add AND, NOT, CLK, 7-Segment, and created gates from the single bottom row. Scroll the row horizontally if it has more gates than fit on screen. Drag gates to position them.
- Click a large input circle to toggle it. Use the black **+** and **−** circles at the top of each side bar to add or remove inputs and outputs (up to 18 each).
- Click an output connector and then an input connector to wire them. Either click order works. A wire follows the pointer until the second connector is clicked. Clicking the same connector twice cancels selection. Each input has one wire driver.
- Right-click a gate or wire to remove it. Hold the right mouse button and move across gates or wires to remove multiple targets.
- Use the mouse wheel over the canvas to resize gates.
- **Create Gate** captures the current circuit as a reusable composite with a chosen name and color. Its exposed ports are the connected input and output bank ports. Custom gates appear in the bottom row and can contain other custom gates. Each captured 7-Segment display appears as its own miniature display on the created gate.
- **Settings** changes the background color and wire shape.
- **Save Project** stores a named project. **Projects** loads, deletes, or starts a new project. Named projects auto-save every ten seconds in Godot's `user://projects` directory.

Run the logic check with:

```sh
Godot --headless --path . --script res://_port_check.gd
```
