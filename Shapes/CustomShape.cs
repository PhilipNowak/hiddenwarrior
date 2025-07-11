using Godot;

[GlobalClass]
public partial class CustomShape : CollisionPolygon2D
{
    [Export]
    private Color _color = new Color(1, 0.3f, 0.1f); // Default color

    public Color Color
    {
        get => _color;
        set
        {
            _color = value;
            var polygon = GetNodeOrNull<Polygon2D>("shape");
            if (polygon != null)
            {
                polygon.Color = value;
            }
        }
    }

    public override void _Ready()
    {
        // Called when the node is added to the scene.
        // Initialize the custom shape

    }
}

