package ru.brikster.chatty.papi;

import me.clip.placeholderapi.expansion.PlaceholderExpansion;
import me.clip.placeholderapi.expansion.Relational;
import org.bukkit.entity.Player;
import org.bukkit.plugin.Plugin;
import ru.brikster.chatty.repository.player.PlayerDataRepository;

import javax.inject.Inject;
import javax.inject.Singleton;

@Singleton
public class ChattyPlaceholderApiExpansion extends PlaceholderExpansion implements Relational {

    @Inject private Plugin plugin;
    @Inject private PlayerDataRepository playerDataRepository;

    @Override
    public String getIdentifier() {
        return "chatty";
    }

    @Override
    public String getAuthor() {
        return "Brikster";
    }

    @Override
    public String getVersion() {
        return plugin.getPluginMeta().getVersion();
    }

    @Override
    public String onPlaceholderRequest(Player one, Player two, String params) {
        if (one == null || two == null) {
            return null;
        }
        // %rel_chatty_ignore% - whether the first player ignores the second one
        if (params.equalsIgnoreCase("ignore")) {
            return Boolean.toString(playerDataRepository
                    .isIgnoredPlayer(one.getUniqueId(), two.getUniqueId()));
        }
        return null;
    }

}
