package ru.brikster.chatty.util;

import lombok.experimental.UtilityClass;
import org.bukkit.entity.Player;

@UtilityClass
public class PaperUtil {

    public boolean isSupportAdventure() {
        try {
            // Concatenation to prevent shadow's relocation
            Player.class.getMethod("sendMessage", Class.forName("net".concat(".kyori.adventure.text.Component")));
            return true;
        } catch (NoSuchMethodException | ClassNotFoundException e) {
            return false;
        }
    }

}
