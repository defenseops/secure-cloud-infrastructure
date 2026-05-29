package com.example.cloudapp.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/admin")
public class AdminController {

    @GetMapping("/secret")
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<Map<String, String>> getSecret() {
        return ResponseEntity.ok(Map.of(
                "status", "ok",
                "secret", "admin-only-data"
        ));
    }
}
