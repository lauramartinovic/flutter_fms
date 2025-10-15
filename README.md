This project is part of a bachelor’s thesis and represents a complete mobile system for automated biomechanical movement analysis.  
The application was developed in collaboration with a professional kinesiologist, with the goal of making **Functional Movement Screening (FMS)** available on mobile devices in a precise, objective, and accessible way.

The app uses **Google ML Kit Pose Detection** to detect human body landmarks in real time and leverages a custom-built analysis layer to measure angles, stability, and movement quality, assigning a functional movement score similar to professional screening methods used in sports and rehabilitation.

---

## **Core Features**

### **Real-time pose estimation**
- Live camera stream with ML-powered landmark detection.

### 🦵 **ASLR (Active Straight Leg Raise)** & **Squat** screening
- Automatic scoring logic implemented for two core FMS exercises:
  - ASLR → hip flexion angle, trunk stability, knee extension.  
  - Squat → depth, torso upright angle, symmetry.

### **Automatic scoring**
- Geometric rules determine the base score.  
- Stability and straightness constraints downgrade scores.  
- Self-reported pain overrides everything and returns score 0.

### **Angle & stability metrics**
- Hip flexion  
- Knee extension ratios  
- Trunk stability (instability % variation)  
- Depth of squat (knee angles)  
- Torso upright angle  
- Repetition counting (for squat)

### **Recording & analysis**
- The app performs live pose detection during recording.  
- When recording stops, the already collected frames are automatically analyzed and scored. 

### **Secure session history**
- All sessions are saved per user account, enabling:
  - Long-term tracking of mobility improvements  
  - Data analysis  
  - Comparison over time

### **Self-report pain integration**
- Before scoring, the user can eport pain (e.g., lower back, hamstrings).  
- If pain is present → score = 0 by FMS standards.

### **Feedback generation**
- After analysis, the app generates personalized feedback based on the score.

---

## **Architecture Overview**

The app is developed in Flutter for full cross-platform support (**Android & iOS**).

### **Presentation layer**
- Flutter UI with real-time camera preview and skeleton overlay.  
- `PosePainter` widget draws lines and points on the live camera feed.

### **Camera & streaming**
- Uses the `camera` plugin for preview and image stream.  
- **iOS**: image stream + recording simultaneously.  
- **Android**: fallback to **post-hoc ML analysis** after recording to be integrated.

### **Pose detection & analysis**
- Powered by Google ML Kit Pose Detection API.  
- Landmark data processed through a custom `PoseAnalysisUtils` class.  
- Handles joint angle calculation, stability metrics, thresholds, and scoring.

### **Data layer (cloud)**
- Firebase Authentication → secure user management.  
- Cloud Firestore → storing session metadata, scores, features, pain reports, and feedback.  
- Designed to support further statistical or ML analysis.

### **Scoring logic**
- Implemented through adjustable `Thresholds` constants.  
- Flexibility to update biomechanical criteria (e.g., hip flexion angle cutoffs).  
- Structured features` map for analytics and debugging.

---

## 📝 **License**

This project was developed as part of a **bachelor’s thesis** at **Sveučilište u Zadru**.  
The application is intended for **educational** and **research** purposes and is **not a certified medical device**.

---