package com.example.feedserver.feed;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class SocialFeedService {

    private SocialFeedRepository feedRepository;

    public SocialFeedService(SocialFeedRepository feedRepository) {
        this.feedRepository = feedRepository;
    }

    public List<SocialFeed> getAllFeeds() {
        return feedRepository.findAll();
    }

    public List<SocialFeed> getAllFeedsByUploaderId(int uploaderId) {
        return feedRepository.findByUploaderId(uploaderId);
    }

    public SocialFeed getFeedById(int feedId) {
        return feedRepository.findById(feedId).orElse(null);
    }

    public void deleteFeed(int feedId) {
        feedRepository.deleteById(feedId);
    }

    @Transactional
    public SocialFeed createFeed(FeedRequest feed) {
        SocialFeed savedFeed = feedRepository.save(new SocialFeed(feed));
        return savedFeed;
    }

}