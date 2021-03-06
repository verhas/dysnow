package javax0.dospexml.commands.basic;

import javax0.dospexml.api.Command;
import javax0.dospexml.api.CommandContext;
import javax0.dospexml.api.CommandResult;
import javax0.dospexml.support.Convert;

import java.math.BigDecimal;
import java.util.List;
import java.util.function.BiFunction;
import java.util.function.Function;

public class Add implements Command<Number> {

    @Override
    public CommandResult<Number> evaluate(CommandContext ctx, List<CommandResult<?>> results) {
        boolean hasDouble = false;
        boolean hasBigDecimal = false;
        boolean hasLong = false;
        for (final var result : results) {
            if (result.type() == BigDecimal.class) {
                hasBigDecimal = true;
                break;// this is the highest priority, we convert all to BigDecimal in this case
            } else if (result.type() == Double.class) {
                hasDouble = true;
            } else if (result.type() == Long.class) {
                hasLong = true;
            } else if (result.type() != Integer.class) {
                throw ctx.exception("I do not know how to add " + result.type());
            }
        }
        if (hasBigDecimal) {
            return addBigDecimals(results);
        }
        if (hasDouble) {
            return addDoubles(results);
        }
        if (hasLong) {
            return addLongs(results);
        }
        return addInts(results);
    }

    private static <T extends Number> CommandResult<T> addAll(List<CommandResult<?>> results,
                                                              T accumulator,
                                                              Function<CommandResult<?>, T> converter,
                                                              BiFunction<T, T, T> sum) {
        for (final var result : results) {
            accumulator = sum.apply(accumulator, converter.apply(result));
        }
        return CommandResult.simple(accumulator);
    }

    private static <T extends Number> CommandResult<T> addBigDecimals(List<CommandResult<?>> results) {
        return (CommandResult<T>) addAll(results, BigDecimal.ZERO, Convert::toBigDecimal, BigDecimal::add);
    }


    private static <T extends Number> CommandResult<T> addDoubles(List<CommandResult<?>> results) {
        return (CommandResult<T>) addAll(results, 0.0, Convert::toDouble, Double::sum);
    }

    private static <T extends Number> CommandResult<T> addLongs(List<CommandResult<?>> results) {
        return (CommandResult<T>) addAll(results, 0L, Convert::toLong, Long::sum);
    }

    private static <T extends Number> CommandResult<T> addInts(List<CommandResult<?>> results) {
        return (CommandResult<T>) addAll(results, 0, Convert::toInt, Integer::sum);
    }

}