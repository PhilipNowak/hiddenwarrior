using System;

namespace HiddenWarrior;

public static class EventManager
{
    public static event Action<Stats> PlayerStatsChanged;

    public static void InvokePlayerStatsChanged(Stats stats) => PlayerStatsChanged?.Invoke(stats);
}
