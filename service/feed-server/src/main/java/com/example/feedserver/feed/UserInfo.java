package com.example.feedserver.feed;

public class UserInfo {

    private int userId;
    private String username;
    private String email;

    public UserInfo() {
    }

    public UserInfo(int userId, String username, String email) {
        this.userId = userId;
        this.username = username;
        this.email = email;
    }

    public int getUserId() {
        return userId;
    }

    public String getUsername() {
        return username;
    }

    public String getEmail() {
        return email;
    }
}