package javax0.dysnow.engine;

import javax0.dysnow.api.Command;
import javax0.dysnow.api.ExecutionException;

import java.net.URI;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

/**
 * A command map contains a mapping between XML tag names and the class that can execute the command the tag
 * represents.
 */
public class CommandMap {

    private static final Map<String,Command<?>> EMPTY = new HashMap<>();

    private final Map<String, Map<String, Command<?>>> map = new HashMap<>();

    public void put(String nsuri, String tag, Command<?> command) throws ExecutionException {
        if (map.computeIfAbsent(nsuri, uri -> new HashMap<>()).put(tag, command) != null) {
            throw new ExecutionException("{" + nsuri.toString() + "}" + tag + " command is already defined");
        }
    }

    public Optional<Command<?>> get(String nsuri, String tag) {
        return Optional.ofNullable(map.computeIfAbsent(nsuri, uri -> EMPTY).computeIfAbsent(tag, t -> null));
    }

}