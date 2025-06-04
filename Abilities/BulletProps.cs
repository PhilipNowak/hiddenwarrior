public class BulletProps
{
    public float damage { get; set; }
    public float speed { get; set; }
    public float scale { get; set; }
    public AnimState anim_idle { get; set; }
}

public class AnimState
{
    public string texture_name { get; set; }
    public string collision { get; set; }
}