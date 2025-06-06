public partial class BulletProps : Godot.GodotObject
{
    public float damage { get; set; }
    public float speed { get; set; }
    public float scale { get; set; }
    //public string anim_idle_texture { get; set; }
    public AnimState anim_idle { get; set; }
}

public partial class AnimState : Godot.GodotObject
{
    public string texture { get; set; }
    public string collision { get; set; }
}