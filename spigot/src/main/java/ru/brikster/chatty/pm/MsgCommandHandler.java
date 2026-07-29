package ru.brikster.chatty.pm;

import cloud.commandframework.context.CommandContext;
import cloud.commandframework.execution.CommandExecutionHandler;
import ru.brikster.chatty.api.adventure.AudienceProvider;
import org.bukkit.command.CommandSender;
import org.jetbrains.annotations.NotNull;
import ru.brikster.chatty.config.file.MessagesConfig;
import ru.brikster.chatty.pm.targets.PmMessageTarget;

import javax.inject.Inject;
import javax.inject.Singleton;

@Singleton
public final class MsgCommandHandler implements CommandExecutionHandler<CommandSender> {

    @Inject private PmMessageService pmMessageService;
    @Inject private PrivateMessageCommandHandler privateMessageCommandHandler;
    @Inject private AudienceProvider audiences;
    @Inject private MessagesConfig messagesConfig;

    @Override
    public void execute(@NotNull CommandContext<CommandSender> commandContext) {
        CommandSender sender = commandContext.getSender();

        String targetName = commandContext.get("target");
        PmMessageTarget target = pmMessageService.resolveTarget(sender, targetName, true);
        if (target == null) {
            audiences.sender(sender).sendMessage(messagesConfig.getPmPlayerNotFound());
            return;
        }

        privateMessageCommandHandler.handleCommand(commandContext, sender, target);
    }

}
