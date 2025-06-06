using Godot;
using HiddenWarrior.Abilities;
using System;

[GlobalClass]
public partial class AbilityBase : Node
{
    [Export]
    public string Id { get; set; }

    [Export]
    public AbilityTypes AbilityType { get; set; }
    [Export]
    private Timer CooldownTimer { get; set; }

    [Export]
    public double CooldownTime { get; set; }

    [Export]
    public NavigationPolygon Pattern { get; set; }
    [Export]
    public PackedDataContainer Bullet { get; set; }

    private bool IsOnCooldown { get; set; } = false;

    public bool Toggle { get; set; }

    public override void _Ready()
    {
        base._Ready();
        CooldownTimer = new Timer()
        {
            WaitTime = CooldownTime,
            Autostart = false,
            OneShot = true
        };
        AddChild(CooldownTimer);
        CooldownTimer.Timeout += CooldownEnd;

        GD.Print("load spawnning resource");

        Pattern.Set("bullet", Id);
        var test = Spawning.GenerateNewBulletProps(Bullet, Id);
        GD.Print(test);
        var aaa = Spawning.CreateBulletPattern(Id, Pattern);
        GD.Print(aaa);

        Spawning.CreateBulletPool(Id, 300, BulletSpawner.Player);
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
            Spawning.Spawn(mousePosition, 0, Id, BulletSpawner.Player);
        }
        else
        {
            Spawning.Spawn(Player.PlayerInstance, Id, BulletSpawner.Player);
        }

        IsOnCooldown = true;
        CooldownTimer.Start(CooldownTime);
    }

}
