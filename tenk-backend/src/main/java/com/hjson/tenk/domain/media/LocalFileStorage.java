package com.hjson.tenk.domain.media;

import com.hjson.tenk.common.config.StorageProperties;
import com.hjson.tenk.common.exception.BusinessException;
import com.hjson.tenk.common.exception.ErrorCode;
import jakarta.annotation.PostConstruct;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;

@Slf4j
@Component
@RequiredArgsConstructor
public class LocalFileStorage {

    private static final DateTimeFormatter DATE_DIR = DateTimeFormatter.ofPattern("yyyy/MM/dd");

    private final StorageProperties properties;
    private Path baseDir;

    @PostConstruct
    void init() throws IOException {
        this.baseDir = Paths.get(properties.baseDir()).toAbsolutePath().normalize();
        Files.createDirectories(this.baseDir);
        log.info("[Storage] baseDir={}", baseDir);
    }

    public StoredFile store(MultipartFile file, String subdirectory) {
        if (file == null || file.isEmpty()) {
            throw new BusinessException(ErrorCode.AMOUNT_VIDEO_REQUIRED);
        }
        String originalName = file.getOriginalFilename();
        String extension = extractExtension(originalName);
        String generatedName = UUID.randomUUID() + extension;
        String relativeDir = subdirectory + "/" + LocalDate.now().format(DATE_DIR);
        Path targetDir = baseDir.resolve(relativeDir).normalize();

        try {
            Files.createDirectories(targetDir);
            Path target = targetDir.resolve(generatedName);
            try (var in = file.getInputStream()) {
                Files.copy(in, target, StandardCopyOption.REPLACE_EXISTING);
            }
            String relative = baseDir.relativize(target).toString().replace('\\', '/');
            return new StoredFile(relative, originalName);
        } catch (IOException e) {
            log.error("[Storage] file save failed", e);
            throw new BusinessException(ErrorCode.MEDIA_UPLOAD_FAILED);
        }
    }

    public Path resolve(String relativePath) {
        Path resolved = baseDir.resolve(relativePath).normalize();
        if (!resolved.startsWith(baseDir)) {
            throw new BusinessException(ErrorCode.MEDIA_NOT_FOUND);
        }
        return resolved;
    }

    public void deleteQuietly(String relativePath) {
        try {
            Files.deleteIfExists(resolve(relativePath));
        } catch (IOException e) {
            log.warn("[Storage] file delete failed: {}", relativePath, e);
        }
    }

    private String extractExtension(String name) {
        if (name == null) return "";
        int idx = name.lastIndexOf('.');
        return idx >= 0 ? name.substring(idx) : "";
    }

    public record StoredFile(String relativePath, String originalName) {}
}
