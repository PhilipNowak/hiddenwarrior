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
        GD.Print("Before set up call");
        SetUpAbility(Player.PlayerInstance.Stats);     
    }

    protected virtual void UpdateAbility(Stats stats)
    {
        var nbr = Pattern.Get("nbr").As<int>();
        Pattern.Set("nbr", nbr + stats.ExtraProjectiles);
    }

    private void SetUpAbility(Stats stats)
    {
        GD.Print("start set up call");
        UpdateAbility(stats);
        
        Godot.Collections.Array<string> array = [Id];
        Pattern.Set("bullet_list", array);
        Spawning.GenerateNewBulletProps(Bullet, Id);
        Spawning.CreateBulletPattern(Id, Pattern);
        Spawning.CreateBulletPool(Id, 300, BulletSpawner.Player);
        CooldownTimer.Timeout += CooldownEnd;
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

        GD.Print("past use");

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
