package com.example.timelineserver.timeline.feed;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;


@Component
public class FeedListener {

    private final ObjectMapper objectMapper;
    private final FeedStore feedStore;

    public FeedListener(ObjectMapper objectMapper, FeedStore feedStore) {
        this.objectMapper = objectMapper;
        this.feedStore = feedStore;
    }

    public void listen(String message) {

    }

}
