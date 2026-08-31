---
name: emumba-java-pojo-to-record
description: Convert simple immutable value-holder POJOs into Java records (Java 16+)
---

# Convert Simple Immutable POJOs to Java Records

## What to look for

A Java class (often a small nested/static helper class) that follows this
exact shape:

- One or more `private final` fields
- A constructor that assigns every field from a same-named/ordered
  parameter, with no other logic
- A public getter for each field (either `getX()` or `x()` naming)
- No other methods besides an optional `toString()`, `equals()`, or
  `hashCode()` override
- No mutable state, no additional business logic

This is the classic "immutable value holder" pattern — the kind of class a
Java developer would write by hand before records existed.

## What to do

Rewrite the class as a Java `record` (available since Java 16). The
record's canonical constructor and accessor methods replace the
hand-written constructor and getters. If the class had a manually written
`toString()`/`equals()`/`hashCode()` that is equivalent to what a record
generates automatically, remove it — the record already provides it.

If the original getter used `getX()` naming and callers depend on that
name, update every call site to use the record's accessor instead (records
generate an accessor named `x()`, not `getX()`) — do not leave call sites
calling a method that no longer exists.

Only apply this transformation if the project's target Java version is 16
or higher (check `maven.compiler.release`/`.source`/`.target` in
`pom.xml`, or the equivalent Gradle property). Do not apply it if
targeting Java 15 or lower — records are not available there.

## Example

Before:

```java
public static class Greeting {
    private final String message;

    public Greeting(String message) {
        this.message = message;
    }

    public String getMessage() {
        return message;
    }

    @Override
    public String toString() {
        return "Greeting{message='" + message + "'}";
    }
}
```

After:

```java
public record Greeting(String message) {
}
```

The record automatically generates a canonical constructor, an accessor
named `message()` (not `getMessage()`), `equals()`, `hashCode()`, and
`toString()` — so the explicit `toString()` override is removed entirely
since the record's generated one is equivalent. Any call site using
`.getMessage()` is updated to `.message()`.
