using Godot;
using System;
using System.Collections.Generic;

public partial class SpawningManager : Node
{
    
    public static Node Instance { get; private set; }

    public override void _EnterTree()
    {
        Instance = GetNode("/root/Spawning"); // Store the reference to your target node
    }

    public void ResetBullets()
    {
        Instance.Call("clear_all_bullets");
    }
}

public enum BulletSpawner {
    Enemy,
    Player
}

public static class Spawning
{
    public static void ClearAllBullets()
    {
        SpawningManager.Instance.Call("clear_all_bullets");
    }

    public static void Spawn(Node spawningNode, string patternId, BulletSpawner spawner = BulletSpawner.Enemy)
    {
        SpawningManager.Instance.Call("spawn", spawningNode, patternId, GetCollisionArea(spawner));
    }

    public static void Spawn(Vector2 position, int rotation, string patternId, BulletSpawner spawner = BulletSpawner.Enemy)
    {
        var dict = new Godot.Collections.Dictionary()
        {
            {"position", position},
            {"rotation", rotation}
        };

        SpawningManager.Instance.Call("spawn", dict, patternId, GetCollisionArea(spawner));
    }

    public static void CreateBulletPool(string bulletId, int number, BulletSpawner spawner)
    {
        SpawningManager.Instance.Call("create_pool", bulletId, GetCollisionArea(spawner), number);
    }

    public static Variant CreateBulletPattern(string id, string bulletId, PatternType type)
    {
        var pattern = "";

        if (type == PatternType.Circle)
        {
            pattern = "PatternCircle";    
        }
        else if (type == PatternType.Line)
        {
            pattern = "PatternLine";
        }
        else if (type == PatternType.One)
        {
            pattern = "PatternOne";
        }

        var createdPattern = SpawningManager.Instance.Call("create_pattern", pattern);

        var patternProps = createdPattern.As<Godot.Collections.Dictionary>();
        // if (patternProps != null)
        // {
        //     patternProps["nbr"] = 7;
        //     patternProps["bullet"] = bulletId;
        // }

        var sanitizedPattern = SpawningManager.Instance.Call("sanitize_pattern", createdPattern, SpawningManager.Instance);

        var newPattern = SpawningManager.Instance.Call("new_pattern", id,  sanitizedPattern);

        return newPattern;
    }

    public static Variant GenerateNewBulletProps(BulletProps props, string id)
    {
        var bulletProps = SpawningManager.Instance.Call("generate_new_bulletprops");
        // var dict = bulletProps.As<Godot.Collections.Dictionary>();
        var dict = bulletProps.Obj as Godot.Collections.Dictionary;
        if (dict != null)
        {
            dict["damage"] = props.damage;
            dict["speed"] = props.speed;
            dict["scale"] = props.scale;
            // dict["anim_idle"] = new Godot.Collections.Dictionary
            // {
            //     {"texture_name", props.anim_idle.texture_name},
            //     {"collision", props.anim_idle.collision}
            // };
            //return dict;
        }

        var sanitizedPattern = SpawningManager.Instance.Call("sanitize_bulletprops", bulletProps, id, SpawningManager.Instance);
        var test = SpawningManager.Instance.Call("new_bullet", id, sanitizedPattern);
        
        return test;

    }

    private static string GetCollisionArea(BulletSpawner spawner)
    {
        return spawner == BulletSpawner.Enemy ? "0" : "2";
    }
}