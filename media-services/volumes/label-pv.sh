#!/usr/bin/env bash
kubectl label persistentvolume video-series-pv pv-name=video-series-pv
kubectl label persistentvolume video-anime-pv pv-name=video-anime-pv
kubectl label persistentvolume video-movies-pv pv-name=video-movies-pv
kubectl label persistentvolume downloads-pv pv-name=downloads-pv
