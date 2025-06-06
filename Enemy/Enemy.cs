using Godot;
using System;

public partial class Enemy : CharacterBody2D
{
    [Export]
    public CustomShape CustomShape { get; set; }
    [Export]
    public Color Color { get; set; } = new Color(1, 1, 1); // Default color

    public bool IsEnemy { get; } = true;
    public int Health { get; set; } = 100;


    public override void _Ready()
    {
        // Called when the node is added to the scene.
        // Initialize the enemy
        //var polygon = GetNodeOrNull<Polygon2D>("Polygon2D");
        //var polygon = CollisionPolygon.GetNodeOrNull<Polygon2D>("Polygon2D");
        CustomShape.Color = Color;
        Spawning.Spawn(this, "line_left");
        //CustomShape.Scale *= 4;
        //polygon.Color = Color;
    }

    public void Hit(int damage)
    {
        Health -= damage;
        if (Health <= 0)
        {

            Spawning.ClearAllBullets();
            QueueFree(); // Remove the enemy from the scene
        }
        else
        {
            GD.Print($"Enemy hit! Remaining health: {Health}");
        }
    }
}
