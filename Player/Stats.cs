using Godot;
using HiddenWarrior;
using System;

public partial class Stats : Node
{

    public int Health { get; set; } = 100;

    private int _maxHealth;

    [Export]
    public int MaxHealth
    {
        get => _maxHealth;
        set
        {
            if (_maxHealth != value)
            {
                _maxHealth = value;
                EventManager.InvokePlayerStatsChanged(this);
            }
        }
    }

    private int _ExtraProjectiles;

    [Export]
    public int ExtraProjectiles
    {
        get => _ExtraProjectiles; set
        {
            if (_ExtraProjectiles != value) // Check if the value has actually changed
            {
                _ExtraProjectiles = value;
                // 3. Emit the signal (fire the event)
                EventManager.InvokePlayerStatsChanged(this);
            }
        }
    }
    
    public override void _Ready()
    {
        Health = MaxHealth;
        // Initialize stats or perform any setup needed
    }
}
