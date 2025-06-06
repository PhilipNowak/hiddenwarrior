using Godot;
using System;

public partial class Stats : Node
{

    public int Health { get; set; } = 100;

    [Export]
    public int MaxHealth { get; set; } = 100;
    
    public override void _Ready()
    {
        Health = MaxHealth;
        // Initialize stats or perform any setup needed
    }
}
