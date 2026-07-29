package ru.brikster.chatty.api.adventure;

import net.kyori.adventure.audience.Audience;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.jetbrains.annotations.NotNull;

import java.util.function.Predicate;

/**
 * Resolves Bukkit command senders to native Adventure audiences.
 */
public interface AudienceProvider {

    @NotNull Audience all();

    @NotNull Audience console();

    @NotNull Audience player(@NotNull Player player);

    @NotNull Audience sender(@NotNull CommandSender sender);

    @NotNull Audience filter(@NotNull Predicate<CommandSender> filter);

}
