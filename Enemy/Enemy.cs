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
        GD.Print("Enemy initialized");
        //var polygon = GetNodeOrNull<Polygon2D>("Polygon2D");
        //var polygon = CollisionPolygon.GetNodeOrNull<Polygon2D>("Polygon2D");
        CustomShape.Color = Color;
        //CustomShape.Scale *= 4;
        //polygon.Color = Color;
    }

    public void Hit(int damage)
    {
        Health -= damage;
        if (Health <= 0)
        {
            GD.Print("Enemy defeated");
            var gdscript = GetNode("/root/Spawning"); //ResourceLoader.Load("res://addons/BulletUpHell/BuHSpawner.gd") as Script; //
            GD.Print(gdscript);
            gdscript.Call("clear_all_bullets"); // Notify the manager that the enemy is defeated
            QueueFree(); // Remove the enemy from the scene
        }
        else
        {
            GD.Print($"Enemy hit! Remaining health: {Health}");
        }
    }
}
