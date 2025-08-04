package com.example.userserver.user;

public class UserRequest {
    private String username;
    private String email;
    private String plainPassword;

    public String getUsername() {
        return username;
    }

    public String getEmail() {
        return email;
    }

    public String getPlainPassword() {
        return plainPassword;
    }
}