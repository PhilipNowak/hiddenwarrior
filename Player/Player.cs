using Godot;
using System;

public partial class Player : CharacterBody2D
{
    [Export]
    public CustomShape CustomShape { get; set; }
    [Export]
    public Color Color { get; set; } = new Color(1, 1, 1); // Default color

    private float _speed = 400.0f;

    public override void _PhysicsProcess(double delta)
    {
        base._PhysicsProcess(delta);
        OnAbilityInput();
        // Handle player movement
        Vector2 velocity = new Vector2();

        if (Input.IsActionPressed("ui_right"))
        {

            velocity.X += 1;
        }
        if (Input.IsActionPressed("ui_left"))
        {
            velocity.X -= 1;
        }
        if (Input.IsActionPressed("ui_down"))
        {
            velocity.Y += 1;
        }
        if (Input.IsActionPressed("ui_up"))
        {
            velocity.Y -= 1;
        }

        // Normalize the velocity vector to ensure consistent speed in all directions
        // Normalize the velocity vector to ensure consistent speed in all directions
        if (velocity.Length() > 0)
        {
            velocity = velocity.Normalized();
        }

        // Scale the velocity by the speed
        velocity *= _speed;
        // Assign velocity to the CharacterBody2D's Velocity property
        //Velocity = velocity;

        // Move the player
        MoveAndCollide(velocity * (float)delta); // Adjust speed and up direction as necessary
    }

    [Export]
    public PackedScene abilityOne { get; set; }

    private void UseAbility()
    {
        // Implement ability usage logic here
        var fireSquare = abilityOne.Instantiate<FireSquare>();
        if (fireSquare != null)
        {
            var mousePosition = GetViewport().GetMousePosition();
            Vector2 direction = (mousePosition - Position).Normalized();
            fireSquare.Position = Position; // Set the position of the fire square to the player's position
            fireSquare.SetDirection(direction); // Set the direction of the fire square
            GetParent().AddChild(fireSquare); // Add the fire square to the scene
        }
        else
        {
            GD.PrintErr("Failed to instantiate FireSquare!");
        }
    }
    private void OnAbilityInput()
    {
        if (Input.IsActionJustPressed("ability_one"))
        {
            //GD.Print("Ability one pressed!");
            UseAbility();
        }

    }

    public override void _Ready()
    {
        CustomShape.Color = Color;
    }
}
