package com.example.timelineserver.timeline;

import com.example.timelineserver.timeline.feed.FeedInfo;
import com.example.timelineserver.timeline.feed.FeedStore;
import com.example.timelineserver.timeline.follow.FollowerStore;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.stream.Collectors;
import java.util.stream.Stream;

@Service
public class TimelineService {

    private final FeedStore feedStore;
    private final FollowerStore followerStore;

    public TimelineService(FeedStore feedStore, FollowerStore followerStore) {
        this.feedStore = feedStore;
        this.followerStore = followerStore;
    }

    public List<SocialPost> listUserFeed(String userId) {
        List<FeedInfo> feedList = feedStore.listFeed(userId);
        Map<Integer, Long> likes = feedStore.countLikes(feedList.stream().map(FeedInfo::getFeedId).toList());
        return feedList.stream().map(
                post -> new SocialPost(post, likes.getOrDefault(post.getFeedId(), 0L))
        ).toList();
    }

    public List<SocialPost> getRandomPost(String userId, double randomPost) {
        List<SocialPost> myPost = userId.equals("none") ? List.of() : listMyFeed(userId);
        int randomPostSize = Math.max(10, (int)Math.ceil(myPost.size() * randomPost));
        List<SocialPost> allPost = new ArrayList<>(listAllFeed());

        Set<Integer> myPostIds = myPost.stream()
                .map(SocialPost::getFeedId)
                .collect(Collectors.toSet());

        allPost.removeIf(post -> myPostIds.contains(post.getFeedId()));

        List<SocialPost> picked;
        if (randomPostSize >= allPost.size()) {
            picked = allPost;
        } else {
            Collections.shuffle(allPost);
            picked = new ArrayList<>(allPost.subList(0, randomPostSize));
        }

        allPost.removeIf(post -> myPostIds.contains(post.getFeedId()));

        return Stream.concat(myPost.stream(), picked.stream())
                .sorted(Comparator.comparing(SocialPost::getUploadDatetime).reversed())
                .collect(Collectors.toList());
    }

    public List<SocialPost> listFollowerFeed(Set<String> followerSet) {
        return followerSet
                .stream()
                .map(this::listUserFeed)
                .filter(Objects::nonNull) // Filter out any nulls that might have resulted from invalid ids
                .flatMap(List::stream) // Flatten the stream of lists into a stream of SocialPost
                .collect(Collectors.toList());
    }

    public List<SocialPost> listMyFeed(String userId) {
        Set<String> followers = followerStore.listFollower(String.valueOf(userId));
        List<SocialPost> myPost = listUserFeed(userId);
        List<SocialPost> followerFeed = listFollowerFeed(followers);

        return Stream.concat(myPost.stream(), followerFeed.stream())
                .sorted(Comparator.comparing(SocialPost::getUploadDatetime).reversed())
                .collect(Collectors.toList());
    }

    public List<SocialPost> listAllFeed() {
        List<FeedInfo> feedList = feedStore.allFeed();
        Map<Integer, Long> likes = feedStore.countLikes(feedList.stream().map(FeedInfo::getFeedId).toList());
        return feedList.stream().map(
                post -> new SocialPost(post, likes.getOrDefault(post.getFeedId(), 0L))
        ).toList();
    }

    public boolean likePost(int userId, int postId) {
        if (feedStore.isLikePost(userId, postId)) {
            feedStore.unlikePost(userId, postId);
            return false;
        } else {
            feedStore.likePost(userId, postId);
            return true;
        }
    }

    public Long countLike(int postId) {
        return feedStore.countLikes(postId);
    }

}
