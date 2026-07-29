package ru.brikster.chatty.adventure;

import net.kyori.adventure.audience.Audience;
import org.bukkit.Bukkit;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.jetbrains.annotations.NotNull;
import ru.brikster.chatty.api.adventure.AudienceProvider;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Predicate;

/**
 * Paper-native audience provider. Paper command senders implement Adventure's
 * {@link Audience} interface directly, so no platform bridge is required.
 */
public final class NativeBukkitAudienceProvider implements AudienceProvider {

    @Override
    public @NotNull Audience all() {
        List<Audience> audiences = new ArrayList<>(Bukkit.getOnlinePlayers());
        audiences.add(Bukkit.getConsoleSender());
        return Audience.audience(audiences);
    }

    @Override
    public @NotNull Audience console() {
        return Bukkit.getConsoleSender();
    }

    @Override
    public @NotNull Audience player(@NotNull Player player) {
        return player;
    }

    @Override
    public @NotNull Audience sender(@NotNull CommandSender sender) {
        return sender;
    }

    @Override
    public @NotNull Audience filter(@NotNull Predicate<CommandSender> filter) {
        List<Audience> audiences = new ArrayList<>();
        for (Player player : Bukkit.getOnlinePlayers()) {
            if (filter.test(player)) {
                audiences.add(player);
            }
        }
        if (filter.test(Bukkit.getConsoleSender())) {
            audiences.add(Bukkit.getConsoleSender());
        }
        return Audience.audience(audiences);
    }

}
