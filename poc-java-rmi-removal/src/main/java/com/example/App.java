package com.example;

public class App {

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

    public static Greeting greet(String name) throws Exception {
        String displayName = (name == null || name.isEmpty()) ? "world" : name;
        return new Greeting("Hello, " + displayName + "!");
    }

    public static void main(String[] args) throws Exception {
        Greeting result = greet("AWS Transform");
        if (!result.getMessage().equals("Hello, AWS Transform!")) {
            throw new AssertionError("unexpected: " + result);
        }
        Greeting defaultResult = greet(null);
        if (!defaultResult.getMessage().equals("Hello, world!")) {
            throw new AssertionError("unexpected: " + defaultResult);
        }
        System.out.println("local-invoke: all assertions passed");
    }
}
