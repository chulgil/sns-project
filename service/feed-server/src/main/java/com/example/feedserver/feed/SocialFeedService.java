package com.example.feedserver.feed;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.client.RestClient;

import java.util.List;

@Service
public class SocialFeedService {

    private SocialFeedRepository feedRepository;

    @Value("${sns.user-server}")
    private String userServerUrl;
    private RestClient restClient = RestClient.create();

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

    public UserInfo getUserInfo(int userId) {
        return restClient.get()
            .uri(userServerUrl + "/api/users/" + userId)
            .retrieve()
            .onStatus(HttpStatusCode::isError, (request, response) -> {
                throw new RuntimeException("invalid server response " + response.getStatusText());
            })
            .body(UserInfo.class);
    }

}