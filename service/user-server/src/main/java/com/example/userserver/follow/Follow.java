package com.example.userserver.follow;

import jakarta.persistence.*;

import java.time.ZonedDateTime;

@Entity
@Table
public class Follow {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private int followId;
    private int userId;
    private int followerId;
    @Temporal(TemporalType.TIMESTAMP)
    private ZonedDateTime followDatetime;

    public Follow() {
    }

    public Follow(int userId, int followerId) {
        this.userId = userId;
        this.followerId = followerId;
    }

    @PrePersist
    protected void onCreate() {
        followDatetime = ZonedDateTime.now();
    }


}