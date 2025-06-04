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
        SpawningManager.Instance.Call("spawn", spawningNode, patternId, spawner == BulletSpawner.Enemy ? "0" : "2");
    }

     public static void Spawn(Vector2 position, int rotation, string patternId, BulletSpawner spawner = BulletSpawner.Enemy)
    {
        var dict = new Godot.Collections.Dictionary()
        {
            {"position", position},
            {"rotation", rotation}
        };

        SpawningManager.Instance.Call("spawn", dict, patternId, spawner == BulletSpawner.Enemy ? "0" : "2");
    }
}