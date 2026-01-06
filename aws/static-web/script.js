// Configuration - Update these URLs after deployment
const API_GATEWAY_URL = 'https://24v19wx2lj.execute-api.af-south-1.amazonaws.com/prod';
const UPLOAD_BUCKET = 'chicago-crimes-uploads-bucket';

document.addEventListener('DOMContentLoaded', function() {
    const fileInput = document.getElementById('fileInput');
    const fileInfo = document.getElementById('fileInfo');
    const fileName = document.getElementById('fileName');
    const submitBtn = document.getElementById('submitBtn');
    const uploadForm = document.getElementById('uploadForm');
    const loading = document.getElementById('loading');
    const results = document.getElementById('results');

    // Handle file selection
    fileInput.addEventListener('change', async function(e) {
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

            // Validate file content and structure
            const validationResult = await validateFileContent(file);
            if (!validationResult.isValid) {
                alert(validationResult.error);
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

        // Step 2: Upload directly to S3 using presigned URL
        updateProgress(2);

        const uploadResponse = await fetch(uploadUrl, {
            method: 'PUT',
            body: file,
            headers: {
                'Content-Type': file.type || 'text/csv'
            }
        });

        if (!uploadResponse.ok) {
            throw new Error('Failed to upload file to S3');
        }

        // Step 3: Wait for S3 trigger Lambda to process file
        updateProgress(3);

        // Poll for results (S3 trigger Lambda processes automatically)
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
                    } else if (results.status === 'error') {
                        throw new Error(results.error || 'File processing failed');
                    }
                }

                // Wait before next attempt
                await new Promise(resolve => setTimeout(resolve, interval));
            } catch (error) {
                if (error.message.includes('Corrupted gzip file') || error.message.includes('CRC check failed')) {
                    throw error; // Don't retry for corruption errors
                }
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

    // Comprehensive file validation
    async function validateFileContent(file) {
        const label = document.querySelector('.file-input-label span');
        const originalText = label.textContent;

        try {
            label.textContent = '🔍 Checking file format...';

            let csvText;

            // Handle gzip files
            if (file.name.toLowerCase().endsWith('.csv.gz')) {
                label.textContent = '📦 Loading decompression library...';
                await loadPako();

                label.textContent = '🔓 Decompressing file...';
                const arrayBuffer = await file.arrayBuffer();
                const bytes = new Uint8Array(arrayBuffer);

                // Check gzip magic number
                if (bytes.length < 10 || bytes[0] !== 0x1f || bytes[1] !== 0x8b) {
                    return { isValid: false, error: 'Invalid gzip file format.' };
                }

                // Decompress and validate
                try {
                    const decompressed = pako.inflate(bytes, { to: 'string' });
                    csvText = decompressed;
                } catch (pakoError) {
                    return { isValid: false, error: 'Corrupted gzip file. Please re-compress and try again.' };
                }
            } else {
                label.textContent = '📄 Reading CSV file...';
                csvText = await file.text();
            }

            label.textContent = '✅ Validating structure...';
            // Validate CSV structure and required columns
            const validation = validateCSVStructure(csvText);
            label.textContent = originalText;
            return validation;

        } catch (error) {
            console.error('File validation error:', error);
            label.textContent = originalText;
            return { isValid: false, error: 'Failed to validate file. Please try again.' };
        }
    }

    // Validate CSV structure and required columns
    function validateCSVStructure(csvText) {
        try {
            const lines = csvText.trim().split('\n');

            if (lines.length < 2) {
                return { isValid: false, error: 'File must contain at least a header and one data row.' };
            }

            // Parse header using proper CSV parsing
            const header = parseCSVRow(lines[0]);

            // Required columns based on the notebook
            const requiredColumns = [
                'date', 'primary_type', 'location_description',
                'arrest', 'domestic', 'district', 'ward',
                'community_area', 'fbi_code'
            ];

            // Check for missing required columns
            const missingColumns = requiredColumns.filter(col =>
                !header.some(h => h.toLowerCase() === col.toLowerCase())
            );

            if (missingColumns.length > 0) {
                return {
                    isValid: false,
                    error: `Missing required columns: ${missingColumns.join(', ')}. Required columns are: ${requiredColumns.join(', ')}.`
                };
            }

            // Validate data format in first few rows (skip empty lines)
            const sampleRows = lines.slice(1, Math.min(4, lines.length)).filter(line => line.trim());
            for (let i = 0; i < sampleRows.length; i++) {
                const row = parseCSVRow(sampleRows[i]);

                if (row.length !== header.length) {
                    return {
                        isValid: false,
                        error: `Row ${i + 2} has ${row.length} columns but header has ${header.length} columns. Please check your CSV format.`
                    };
                }
            }

            return { isValid: true };

        } catch (error) {
            console.error('CSV validation error:', error);
            return { isValid: false, error: 'Invalid CSV format. Please check your file structure.' };
        }
    }

    // Simple CSV row parser that handles quoted fields
    function parseCSVRow(row) {
        const result = [];
        let current = '';
        let inQuotes = false;

        for (let i = 0; i < row.length; i++) {
            const char = row[i];

            if (char === '"') {
                inQuotes = !inQuotes;
            } else if (char === ',' && !inQuotes) {
                result.push(current.trim());
                current = '';
            } else {
                current += char;
            }
        }

        result.push(current.trim());
        return result;
    }

    // Load pako library dynamically
    async function loadPako() {
        if (typeof pako !== 'undefined') {
            return; // Already loaded
        }

        return new Promise((resolve, reject) => {
            const script = document.createElement('script');
            script.src = 'https://cdnjs.cloudflare.com/ajax/libs/pako/2.1.0/pako.min.js';
            script.onload = resolve;
            script.onerror = reject;
            document.head.appendChild(script);
        });
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
