package com.example.timelineserver.timeline.follow;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

import java.util.Set;

@Component
public class FollowerStore {

    private final StringRedisTemplate redis;
    private final ObjectMapper objectMapper;

    public FollowerStore(StringRedisTemplate redis, ObjectMapper objectMapper) {
        this.redis = redis;
        this.objectMapper = objectMapper;
    }

    public void followUser(FollowMessage followMessage) {

    }

    public Set<String> listFollower(String userId) {

        return Set.of();
    }

}
