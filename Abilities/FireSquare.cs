using Godot;
using System;

public partial class FireSquare : Node2D, IAbility
{
    // Size of the fire square
    [Export]
    public Vector2 Size { get; set; } = new Vector2(32, 32);


    // FireSquare class that implements IAbility interface
    public float Speed = 800.0f; // Speed of the fire square
    public float Duration = 2.0f; // Duration of the fire square's existence
    public float Damage = 10.0f; // Damage dealt by the fire square
    private Vector2 _direction; // Direction of the fire square
    private float _timer; // Timer to track the duration of the fire square
    private Vector2 _velocity; // Velocity of the fire square

    public bool IsFromPlayer { get; set; }
    public bool IsActive { get; set; }

    public override void _Ready()
    {
        var square = GetNodeOrNull<Node2D>("Shape");
        if (square != null)
        {
            
            square.Scale = square.Scale / 4f;
            var shape = square.GetNodeOrNull<Polygon2D>("shape");
            if (shape != null)
            {
                shape.Color = new Color(1, 0.3f, 0.1f); // Set to a fiery orange-red color
                //shape.Modulate = new Color(1, 0.3f, 0.1f); // Set to a fiery orange-red color
                //shape.Color = new Color(1, 0.3f, 0.1f); // Set to a fiery orange-red color
            }
            //square.Scale = Size / new Vector2(64, 64); // Scale the square to the desired size
        }
        // Called when the node is added to the scene.
        // Initialize the fire square
        IsActive = true;
        _timer = Duration;
        _velocity = new Vector2(Speed, 0); // Set initial velocity
    }
    public override void _PhysicsProcess(double delta)
    {
        // Called every frame. 'delta' is the elapsed time since the previous frame.
        if (IsActive)
        {
            _velocity = _direction * Speed;
            // Move the fire square
            Position += _velocity * (float)delta;

            // Update the timer
            _timer -= (float)delta;
            if (_timer <= 0)
            {
                // Deactivate the fire square after its duration
                IsActive = false;
                QueueFree(); // Remove the fire square from the scene
            }
        }
    }

    public void SetDirection(Vector2 direction)
    {
        // Set the direction of the fire square
        _direction = direction.Normalized();
        _velocity = _direction * Speed; // Update velocity based on direction
    }
    public void OnAreaEntered(Area2D area)
    {
        GD.Print("Area entered: " + area.Name);
        // Handle collision with other areas
        if (area.IsInGroup("Player"))
        {
            // Deal damage to the player
            Player player = area.GetParent<Player>();
            if (player != null)
            {
                //player.TakeDamage(Damage);
                GD.Print("Dealing damage to player: " + Damage);
            }
        }
    }
}
