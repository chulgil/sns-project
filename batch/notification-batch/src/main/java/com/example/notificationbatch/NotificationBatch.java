package com.example.notificationbatch;

import org.springframework.batch.core.Job;
import org.springframework.batch.core.Step;
import org.springframework.batch.core.job.builder.JobBuilder;
import org.springframework.batch.core.launch.support.RunIdIncrementer;
import org.springframework.batch.core.repository.JobRepository;
import org.springframework.batch.core.step.builder.StepBuilder;
import org.springframework.batch.item.ItemReader;
import org.springframework.batch.item.ItemWriter;
import org.springframework.batch.item.database.JdbcCursorItemReader;
import org.springframework.batch.item.database.builder.JdbcCursorItemReaderBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.BeanPropertyRowMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.transaction.PlatformTransactionManager;

import javax.sql.DataSource;
import java.time.ZonedDateTime;

@Configuration
public class NotificationBatch {

    @Bean
    public JdbcCursorItemReader<NotificationInfo> reader(DataSource dataSource) {
        return new JdbcCursorItemReaderBuilder<NotificationInfo>().name("followerReader")
            .dataSource(dataSource)
            .sql("""
                 SELECT f.follow_id, u.email, u.username, f.follower_id, u2.username as follower_name, f.follow_datetime
                 FROM follow f, user u, user u2
                 WHERE f.user_id = u.user_id and f.follower_id = u2.user_id and f.mail_sent_datetime is null;
                 """)
            .rowMapper(new BeanPropertyRowMapper<>(NotificationInfo.class))
            .build();
    }

    @Bean
    public ItemWriter<NotificationInfo> sendMail(JavaMailSender mailSender, JdbcTemplate jdbcTemplate) {
        return items -> {
            for (NotificationInfo item : items) {
                SimpleMailMessage message = new SimpleMailMessage();
                message.setFrom("jheo.aws@gmail.com");
                message.setTo(item.getEmail());
                message.setSubject("New Follower!");
                message.setText("Hello, " + item.getUsername() + "! @" + item.getFollowerName() + " is now follow you!");
                mailSender.send(message);

                jdbcTemplate.update(
                    "UPDATE follow SET mail_sent_datetime = ? WHERE follow_id = ?", ZonedDateTime.now(), item.getFollowId());
            }
        };
    }

    @Bean
    public Step notificationStep(JobRepository jobRepository,
                                 PlatformTransactionManager transactionManager,
                                 ItemReader<NotificationInfo> itemReader,
                                 ItemWriter<NotificationInfo> itemWriter) {

        return new StepBuilder("mail-send-step", jobRepository).<NotificationInfo, NotificationInfo>chunk(10, transactionManager)
            .reader(itemReader)
            .writer(itemWriter)
            .build();
    }

    @Bean
    public Job notificationJob(Step notificationStep, JobRepository jobRepository) {
        return new JobBuilder("mail-send-job", jobRepository).incrementer(new RunIdIncrementer()).start(notificationStep).build();
    }


}