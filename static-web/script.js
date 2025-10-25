// Configuration - Update these URLs after deployment
const API_GATEWAY_URL = 'https://your-api-gateway-url.amazonaws.com/prod';
const UPLOAD_BUCKET = 'chicago-crimes-uploads';

document.addEventListener('DOMContentLoaded', function() {
    const fileInput = document.getElementById('fileInput');
    const fileInfo = document.getElementById('fileInfo');
    const fileName = document.getElementById('fileName');
    const submitBtn = document.getElementById('submitBtn');
    const uploadForm = document.getElementById('uploadForm');
    const loading = document.getElementById('loading');
    const results = document.getElementById('results');

    // Handle file selection
    fileInput.addEventListener('change', function(e) {
        const file = e.target.files[0];
        
        if (file) {
            // Validate file type
            const fileName = file.name.toLowerCase();
            if (!fileName.endsWith('.csv') && !fileName.endsWith('.csv.gz')) {
                alert('Please select a CSV or gzipped CSV file.');
                fileInput.value = '';
                return;
            }
            
            // Validate file size (200MB limit)
            const maxSize = 200 * 1024 * 1024; // 200MB in bytes
            if (file.size > maxSize) {
                alert('File size must be less than 200MB. Please select a smaller file.');
                fileInput.value = '';
                return;
            }
            
            // Show file info
            document.getElementById('fileName').textContent = file.name;
            fileInfo.style.display = 'block';
            submitBtn.disabled = false;
            
            // Update file input label
            const label = document.querySelector('.file-input-label span');
            label.textContent = 'File Selected';
            
        } else {
            // Hide file info
            fileInfo.style.display = 'none';
            submitBtn.disabled = true;
            
            // Reset file input label
            const label = document.querySelector('.file-input-label span');
            label.textContent = 'Choose CSV File';
        }
    });

    // Handle form submission
    uploadForm.addEventListener('submit', async function(e) {
        e.preventDefault();
        
        const file = fileInput.files[0];
        if (!file) {
            alert('Please select a file first.');
            return;
        }
        
        // Show loading animation
        showLoading();
        
        try {
            // Upload file to S3 and get predictions
            const results = await uploadAndPredict(file);
            showResults(results);
        } catch (error) {
            console.error('Error:', error);
            alert('An error occurred while processing your file. Please try again.');
            hideLoading();
        }
    });

    async function uploadAndPredict(file) {
        // Step 1: Get presigned URL for S3 upload
        updateProgress(1);
        
        const presignedResponse = await fetch(`${API_GATEWAY_URL}/get-upload-url`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                filename: file.name,
                contentType: file.type || 'text/csv'
            })
        });
        
        if (!presignedResponse.ok) {
            throw new Error('Failed to get upload URL');
        }
        
        const { uploadUrl, key } = await presignedResponse.json();
        
        // Step 2: Upload file to S3
        updateProgress(2);
        
        const uploadResponse = await fetch(uploadUrl, {
            method: 'PUT',
            body: file,
            headers: {
                'Content-Type': file.type || 'text/csv'
            }
        });
        
        if (!uploadResponse.ok) {
            throw new Error('Failed to upload file');
        }
        
        // Step 3: Wait for processing and get results
        updateProgress(3);
        
        // Poll for results (Lambda processes the file automatically via S3 trigger)
        const results = await pollForResults(key);
        return results;
    }

    async function pollForResults(fileKey, maxAttempts = 30, interval = 2000) {
        for (let attempt = 0; attempt < maxAttempts; attempt++) {
            try {
                const response = await fetch(`${API_GATEWAY_URL}/get-results/${encodeURIComponent(fileKey)}`);
                
                if (response.ok) {
                    const results = await response.json();
                    if (results.status === 'completed') {
                        return results.data;
                    }
                }
                
                // Wait before next attempt
                await new Promise(resolve => setTimeout(resolve, interval));
            } catch (error) {
                console.log(`Polling attempt ${attempt + 1} failed:`, error);
            }
        }
        
        throw new Error('Processing timeout. Please try again.');
    }

    function showLoading() {
        uploadForm.style.display = 'none';
        document.querySelector('.upload-header').style.display = 'none';
        loading.style.display = 'block';
        results.style.display = 'none';
    }

    function hideLoading() {
        loading.style.display = 'none';
        uploadForm.style.display = 'block';
        document.querySelector('.upload-header').style.display = 'block';
    }

    function updateProgress(step) {
        // Reset all steps
        document.querySelectorAll('.step').forEach(s => s.classList.remove('active'));
        
        // Activate steps up to current
        for (let i = 1; i <= step; i++) {
            const stepElement = document.getElementById(`step${i}`) || document.querySelector('.step');
            if (stepElement) {
                stepElement.classList.add('active');
            }
        }
    }

    function showResults(data) {
        loading.style.display = 'none';
        results.style.display = 'block';
        
        // Update result values
        document.getElementById('totalCases').textContent = data.summary.total_cases.toLocaleString();
        document.getElementById('predictedArrests').textContent = data.summary.predicted_arrests.toLocaleString();
        document.getElementById('avgProbability').textContent = (data.summary.avg_probability * 100).toFixed(1) + '%';
        document.getElementById('highRiskCases').textContent = data.summary.high_risk_cases.toLocaleString();
    }

    // Drag and drop functionality
    const uploadCard = document.querySelector('.upload-card');
    const fileInputLabel = document.querySelector('.file-input-label');

    ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
        uploadCard.addEventListener(eventName, preventDefaults, false);
    });

    function preventDefaults(e) {
        e.preventDefault();
        e.stopPropagation();
    }

    ['dragenter', 'dragover'].forEach(eventName => {
        uploadCard.addEventListener(eventName, highlight, false);
    });

    ['dragleave', 'drop'].forEach(eventName => {
        uploadCard.addEventListener(eventName, unhighlight, false);
    });

    function highlight(e) {
        fileInputLabel.style.borderColor = '#667eea';
        fileInputLabel.style.borderStyle = 'dashed';
        fileInputLabel.style.backgroundColor = 'rgba(102, 126, 234, 0.1)';
    }

    function unhighlight(e) {
        fileInputLabel.style.borderColor = 'transparent';
        fileInputLabel.style.backgroundColor = '';
    }

    uploadCard.addEventListener('drop', handleDrop, false);

    function handleDrop(e) {
        const dt = e.dataTransfer;
        const files = dt.files;

        if (files.length > 0) {
            fileInput.files = files;
            
            // Trigger change event
            const event = new Event('change', { bubbles: true });
            fileInput.dispatchEvent(event);
        }
    }
});

// Reset form function
function resetForm() {
    document.getElementById('uploadForm').style.display = 'block';
    document.querySelector('.upload-header').style.display = 'block';
    document.getElementById('loading').style.display = 'none';
    document.getElementById('results').style.display = 'none';
    
    // Reset form fields
    document.getElementById('fileInput').value = '';
    document.getElementById('fileInfo').style.display = 'none';
    document.getElementById('submitBtn').disabled = true;
    document.querySelector('.file-input-label span').textContent = 'Choose CSV File';
}