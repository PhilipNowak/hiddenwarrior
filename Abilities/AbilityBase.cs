using Godot;
using HiddenWarrior.Abilities;
using System;

public partial class AbilityBase : Node
{
    [Export]
    public AbilityTypes AbilityType { get; set; }
    [Export]
    private Timer CooldownTimer { get; set; }

    [Export]
    public double CooldownTime { get; set; }
    private bool IsOnCooldown { get; set; } = false;

    public bool Toggle { get; set; }

    public override void _Ready()
    {
        base._Ready();
        CooldownTimer = new Timer()
        {
            WaitTime = CooldownTime,
            Autostart = true
        };
        AddChild(CooldownTimer);
        CooldownTimer.Timeout += CooldownEnd;

        var test = Spawning.GenerateNewBulletProps(new BulletProps()
        {
            damage = 100,
            speed = 500,
            scale = 1.5f,

        }, "myTestBullet");
        GD.Print(test);
        var aaa = Spawning.CreateBulletPattern("myTestPattern", "myTestBullet", PatternType.Circle);
        GD.Print(aaa);
        
        Spawning.CreateBulletPool("normal", 300, BulletSpawner.Player);
    }


    private void CooldownEnd()
    {
        GD.Print("Cooldown ended");
        IsOnCooldown = false;
    }


    public void Use()
    {
        if (IsOnCooldown)
        {
            return;
        }

        if (AbilityType == AbilityTypes.SpawnAtMouse)
        {
            var mousePosition = GetViewport().GetMousePosition();
            Spawning.Spawn(mousePosition, 0, "myTestPattern", BulletSpawner.Player);
            IsOnCooldown = true;
            CooldownTimer.Start(CooldownTime);
        }
    }

}
