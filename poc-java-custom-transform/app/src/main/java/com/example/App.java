package com.example;

public class App {

    public record Greeting(String message) {
    }

    public static Greeting greet(String name) {
        String displayName = (name == null || name.isEmpty()) ? "world" : name;
        return new Greeting("Hello, " + displayName + "!");
    }

    public static void main(String[] args) {
        Greeting result = greet("AWS Transform");
        if (!result.message().equals("Hello, AWS Transform!")) {
            throw new AssertionError("unexpected: " + result);
        }
        Greeting defaultResult = greet(null);
        if (!defaultResult.message().equals("Hello, world!")) {
            throw new AssertionError("unexpected: " + defaultResult);
        }
        System.out.println("local-invoke: all assertions passed");
    }
}
