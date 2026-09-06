-- Matrix Attual Core
-- Migration 001: extensions

begin;

create extension if not exists pgcrypto;

commit;
