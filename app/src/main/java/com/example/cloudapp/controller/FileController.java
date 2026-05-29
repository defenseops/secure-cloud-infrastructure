package com.example.cloudapp.controller;

import com.example.cloudapp.service.S3Service;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.List;

@RestController
@RequestMapping("/files")
public class FileController {

    private final S3Service s3Service;

    public FileController(S3Service s3Service) {
        this.s3Service = s3Service;
    }

    @GetMapping
    @PreAuthorize("hasAnyRole('VIEWER', 'EDITOR', 'ADMIN')")
    public ResponseEntity<List<String>> listFiles() {
        return ResponseEntity.ok(s3Service.listFiles());
    }

    @PostMapping("/upload")
    @PreAuthorize("hasAnyRole('EDITOR', 'ADMIN')")
    public ResponseEntity<String> uploadFile(@RequestParam("file") MultipartFile file) throws IOException {
        String key = s3Service.uploadFile(file);
        return ResponseEntity.ok("Uploaded: " + key);
    }

    @GetMapping("/download/{filename}")
    @PreAuthorize("hasAnyRole('VIEWER', 'EDITOR', 'ADMIN')")
    public ResponseEntity<byte[]> downloadFile(@PathVariable String filename) {
        var fileBytes = s3Service.downloadFile(filename);
        String contentType = fileBytes.response().contentType();

        HttpHeaders headers = new HttpHeaders();
        headers.setContentDisposition(
            ContentDisposition.attachment().filename(filename).build()
        );
        headers.setContentType(
            contentType != null ? MediaType.parseMediaType(contentType) : MediaType.APPLICATION_OCTET_STREAM
        );

        return ResponseEntity.ok().headers(headers).body(fileBytes.asByteArray());
    }

    @GetMapping("/view/{filename}")
    @PreAuthorize("hasAnyRole('VIEWER', 'EDITOR', 'ADMIN')")
    public ResponseEntity<byte[]> viewFile(@PathVariable String filename) {
        var fileBytes = s3Service.downloadFile(filename);
        String contentType = fileBytes.response().contentType();

        HttpHeaders headers = new HttpHeaders();
        headers.setContentDisposition(
            ContentDisposition.inline().filename(filename).build()
        );
        headers.setContentType(
            contentType != null ? MediaType.parseMediaType(contentType) : MediaType.APPLICATION_OCTET_STREAM
        );

        return ResponseEntity.ok().headers(headers).body(fileBytes.asByteArray());
    }
}
