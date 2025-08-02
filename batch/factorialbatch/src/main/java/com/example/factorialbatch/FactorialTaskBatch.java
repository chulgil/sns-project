package com.example.factorialbatch;

import org.springframework.batch.core.Job;
import org.springframework.batch.core.Step;
import org.springframework.batch.core.job.builder.JobBuilder;
import org.springframework.batch.core.repository.JobRepository;
import org.springframework.batch.core.step.builder.StepBuilder;
import org.springframework.batch.item.ItemProcessor;
import org.springframework.batch.item.ItemReader;
import org.springframework.batch.item.ItemWriter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.transaction.PlatformTransactionManager;

import java.math.BigDecimal;
import java.util.HashMap;
import java.util.Map;

@Configuration
public class FactorialTaskBatch {

    @Bean
    public ItemReader<String> taskReader(StringRedisTemplate redisTemplate) {
        return () -> redisTemplate.opsForSet().pop("factorial:task-queue");
    }

    @Bean
    public ItemProcessor<String, String> taskProcessor() {
        return task -> {
            int n = Integer.parseInt(task);
            BigDecimal result = BigDecimal.ONE;
            for (int i = 2; i < n + 1; i += 1) {
                result = result.multiply(BigDecimal.valueOf(i));
            }

            return task + ":" + result.toPlainString();
        };
    }

    @Bean
    public ItemWriter<String> resultWriter(StringRedisTemplate redisTemplate) {
        return items -> {
            Map<String, String> resultMap = new HashMap<>();
            for (String result : items) {
                String[] factorial = result.split(":");
                resultMap.put(factorial[0], factorial[1]);
            }

            redisTemplate.opsForHash().putAll("factorial:result-set", resultMap);
        };
    }

    @Bean
    public Step factorialStep(JobRepository jobRepository, PlatformTransactionManager transactionManager,
                              ItemReader<String> taskReader,
                              ItemProcessor<String, String> taskProcessor,
                              ItemWriter<String> resultWriter
    ) {
        return new StepBuilder("factorial-step", jobRepository)
                .<String, String>chunk(10, transactionManager)
                .reader(taskReader)
                .processor(taskProcessor)
                .writer(resultWriter)
                .build();
    }

    @Bean
    public Job factorialTaskJob(Step factorialStep, JobRepository jobRepository) {
        return new JobBuilder("factorial-job", jobRepository)
                .start(factorialStep)
                .build();
    }

}
