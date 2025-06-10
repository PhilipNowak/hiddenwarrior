using Godot;
using System;
using System.Dynamic;

public partial class Player : CharacterBody2D
{
    public static Player PlayerInstance { get; private set;}
    [Export]
    public CustomShape CustomShape { get; set; }
    [Export]
    public Color Color { get; set; } = new Color(1, 1, 1); // Default color
    [Export]
    public AbilityBase Ability1 { get; set; }
    [Export]
    public Stats Stats { get; set; }

    private float _speed = 200.0f;

    public override void _PhysicsProcess(double delta)
    {
        base._PhysicsProcess(delta);
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

        if (Input.IsActionPressed("ability_one") && Ability1 != null)
        {
            Ability1.Use();
        }

        // Normalize the velocity vector to ensure consistent speed in all directions
        // Normalize the velocity vector to ensure consistent speed in all directions
        if (velocity.Length() > 0)
        {
            velocity = velocity.Normalized();
        }

        // Scale the velocity by the speed
        velocity *= _speed;

         MoveAndCollide(velocity * (float)delta); // Adjust speed and up direction as necessary

    }

    public void Hit(int damage)
    {
        Stats.Health -= damage;
        if (Stats.Health <= 0)
        {
            GD.Print("Player defeated");
            QueueFree(); // Remove the player from the scene
        }
        else
        {
            GD.Print($"Player hit! Remaining health: {Stats.Health}");
        }
    }

    public override void _EnterTree()
    {
        base._EnterTree();
        PlayerInstance = this;
    }


    public override void _Ready()
    {
        CustomShape.Color = Color;      
    }    
    
}
