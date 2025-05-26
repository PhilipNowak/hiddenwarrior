using Godot;
using System;

public partial class Enemy : CharacterBody2D
{
    [Export]
    public CustomShape CustomShape { get; set; }
    [Export]
    public Color Color { get; set; } = new Color(1, 1, 1); // Default color


    public override void _Ready()
    {
        // Called when the node is added to the scene.
        // Initialize the enemy
        GD.Print("Enemy initialized");
        //var polygon = GetNodeOrNull<Polygon2D>("Polygon2D");
        //var polygon = CollisionPolygon.GetNodeOrNull<Polygon2D>("Polygon2D");
        CustomShape.Color = Color;
        CustomShape.Scale *= 4;
        //polygon.Color = Color;
    }
}
