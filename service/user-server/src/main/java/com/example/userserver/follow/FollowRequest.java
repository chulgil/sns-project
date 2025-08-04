package com.example.userserver.follow;

public class FollowRequest {

    private int userId;
    private int followerId;

    public FollowRequest(int userId, int followerId) {
        this.userId = userId;
        this.followerId = followerId;
    }

    public int getUserId() {
        return userId;
    }

    public int getFollowerId() {
        return followerId;
    }
}