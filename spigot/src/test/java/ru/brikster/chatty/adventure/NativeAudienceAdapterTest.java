package ru.brikster.chatty.adventure;

import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.event.ClickEvent;
import net.kyori.adventure.text.event.HoverEvent;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class NativeAudienceAdapterTest {

    @Test
    void serializesClickAndHoverInLegacyCompatibleSchema() {
        // Regression: NativeAudienceAdapter bridges Chatty's shaded Adventure to
        // the server's (possibly older) native Adventure through JSON. The default
        // gson() serializer emits only the new snake_case click_event/hover_event
        // schema, which an older native Adventure cannot read — it then silently
        // drops every click and hover event (clickable mentions, links, tooltips).
        Component component = Component.text("@Steve")
                .clickEvent(ClickEvent.suggestCommand("/msg Steve "))
                .hoverEvent(HoverEvent.showText(Component.text("Click to PM Steve")));

        String json = NativeAudienceAdapter.serializeForNative(component);

        // The compatibility schema must still carry the camelCase form an older
        // native Adventure (e.g. the one bundled with Paper 26.2) reads.
        assertTrue(json.contains("\"clickEvent\""),
                "legacy camelCase clickEvent missing from bridge JSON: " + json);
        assertTrue(json.contains("\"hoverEvent\""),
                "legacy camelCase hoverEvent missing from bridge JSON: " + json);
        assertTrue(json.contains("suggest_command"),
                "click action missing from bridge JSON: " + json);
    }

}
