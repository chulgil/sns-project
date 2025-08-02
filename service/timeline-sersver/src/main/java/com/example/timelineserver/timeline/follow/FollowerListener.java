package com.example.timelineserver.timeline.follow;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;


@Component
public class FollowerListener {

    private final ObjectMapper objectMapper;
    private final FollowerStore followerStore;

    public FollowerListener(ObjectMapper objectMapper, FollowerStore followerStore) {
        this.objectMapper = objectMapper;
        this.followerStore = followerStore;
    }

    public void listen(String message) {

    }

}
